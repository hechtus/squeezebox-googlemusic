package Plugins::GoogleMusic::Plugin;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;
use base qw(Slim::Plugin::OPMLBased);

use Encode qw(decode_utf8);

use Data::Dumper;

use Plugins::GoogleMusic::Settings;
use Scalar::Util qw(blessed);
use Slim::Control::Request;
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(string cstring);
use Slim::Menu::GlobalSearch;

use Plugins::GoogleMusic::GoogleAPI;
use Plugins::GoogleMusic::ProtocolHandler;
use Plugins::GoogleMusic::Image;
use Plugins::GoogleMusic::Library;
use Plugins::GoogleMusic::AllAccess;
use Plugins::GoogleMusic::Playlists;
use Plugins::GoogleMusic::Radio;
use Plugins::GoogleMusic::Recent;
use Plugins::GoogleMusic::TrackMenu;
use Plugins::GoogleMusic::AlbumMenu;
use Plugins::GoogleMusic::ArtistMenu;
use Plugins::GoogleMusic::TrackInfo;
use Plugins::GoogleMusic::AlbumInfo;


my $log;
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();


BEGIN {
	$log = Slim::Utils::Log->addLogCategory({
		'category'     => 'plugin.googlemusic',
		'defaultLevel' => 'WARN',
		'description'  => 'PLUGIN_GOOGLEMUSIC',
	});
}

sub getDisplayName {
	return 'PLUGIN_GOOGLEMUSIC';
}

sub initPlugin {
	my $class = shift;

	# Chech version of gmusicapi first
	if (!blessed($googleapi) || (Plugins::GoogleMusic::GoogleAPI::get_version() lt '3.1.0')) {
		$class->SUPER::initPlugin(
			tag    => 'googlemusic',
			feed   => \&badVersion,
			is_app => 1,
			weight => 1,
			);
		return;
	}

	$class->SUPER::initPlugin(
		tag    => 'googlemusic',
		feed   => \&toplevel,
		is_app => 1,
		weight => 1,
	);

	if (main::WEBUI) {
		Plugins::GoogleMusic::Settings->new;
	}

	# Initialize submodules
	Plugins::GoogleMusic::Image::init();
	Plugins::GoogleMusic::Radio::init();
	Plugins::GoogleMusic::Recent::init();

	# Try to login. If SSL verification fails, login() raises an
	# exception. Catch it to allow the plugin to be started.
	eval {
		$googleapi->login($prefs->get('username'),
						  $prefs->get('password'));
	};
	if ($@) {
		$log->error("Not able to login to Google Play Music: $@");
	}

	# Refresh My Library and Playlists
	if (!$googleapi->is_authenticated()) {
		$log->error(string('PLUGIN_GOOGLEMUSIC_NOT_LOGGED_IN'));
	} else {
		Plugins::GoogleMusic::Library::refresh();
		Plugins::GoogleMusic::Playlists::refresh();
	}

	Slim::Menu::TrackInfo->registerInfoProvider( googlemusic => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );

	Slim::Menu::GlobalSearch->registerInfoProvider( googlemusic => (
		after => 'middle',
		func  => \&searchInfoMenu,
	) );

	Slim::Control::Request::addDispatch(['googlemusicbrowse', 'items', '_index', '_quantity' ], [0, 1, 1, \&itemQuery]);
	Slim::Control::Request::addDispatch(['googlemusicplaylistcontrol'], [1, 0, 1, \&playlistcontrolCommand]);

	Plugins::GoogleMusic::TrackInfo->init();
	Plugins::GoogleMusic::AlbumInfo->init();

	return;
}

sub shutdownPlugin {
	if (blessed($googleapi)) {
		$googleapi->logout();
	}

	return;
}


sub badVersion {
	my ($client, $callback, $args) = @_;

	my @menu;
	push @menu, {
		name => cstring($client, 'PLUGIN_GOOGLEMUSIC_BAD_VERSION'),
		type => 'text',
		wrap => 1,
	};

	$callback->(\@menu);

	return;
}

sub toplevel {
	my ($client, $callback, $args) = @_;

	my @menu;

	if ($prefs->get('all_access_enabled')) {
		@menu = (
			{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_MY_MUSIC'), type => 'link', url => \&my_music },
			{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_ALL_ACCESS'), type => 'link', url => \&all_access },
		);
		$callback->(\@menu);
	} else {
		# go to my_music directly, making it the top level menu
		my_music($client, $callback, $args);
	}

	return;
}

sub my_music {
	my ($client, $callback, $args) = @_;
	my @menu = (
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_BROWSE'), type => 'link', url => \&search },
		{ name => cstring($client, 'PLAYLISTS'), type => 'link', url => \&Plugins::GoogleMusic::Playlists::feed },
		{ name => cstring($client, 'SEARCH'), type => 'search', url => \&search },
		{ name => cstring($client, 'RECENT_SEARCHES'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentSearchesFeed, passthrough => [ { "all_access" => 0 } ] },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RECENT_ALBUMS'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentAlbumsFeed, passthrough => [ { "all_access" => 0 } ] },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RECENT_ARTISTS'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentArtistsFeed, passthrough => [ { "all_access" => 0 } ] },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RELOAD_LIBRARY'), type => 'func', url => \&reload_library },
	);

	$callback->(\@menu);

	return;
}

sub reload_library {
	my ($client, $callback, $args) = @_;

	Plugins::GoogleMusic::Library::refresh();
	Plugins::GoogleMusic::Playlists::refresh();

	my @menu;
	push @menu, {
		'name' => cstring($client, 'PLUGIN_GOOGLEMUSIC_LIBRARY_RELOADED'),
		'type' => 'text',
	};

	$callback->(\@menu);

	return;
}

sub all_access {
	my ($client, $callback, $args) = @_;
	my @menu = (
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_MY_RADIO_STATIONS'), type => 'link', url => \&Plugins::GoogleMusic::Radio::menu },
		{ name => cstring($client, 'SEARCH'), type => 'search', url => \&search_all_access },
		{ name => cstring($client, 'RECENT_SEARCHES'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentSearchesFeed, passthrough => [ { "all_access" => 1 } ] },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RECENT_ALBUMS'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentAlbumsFeed, passthrough => [ { "all_access" => 1 } ] },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RECENT_ARTISTS'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentArtistsFeed, passthrough => [ { "all_access" => 1 } ] },
	);

	$callback->(\@menu);

	return;
}

sub search {
	my ($client, $callback, $args, $search) = @_;

	$args->{search} ||= $search;

	# The search string may be empty. We could forbid this.
	$args->{search} ||= '';
	my @query = split(' ', $args->{search});

	Plugins::GoogleMusic::Recent::recentSearchesAdd($args->{search}) if scalar @query;

	my ($tracks, $albums, $artists) = Plugins::GoogleMusic::Library::search({'any' => \@query});

	my @menu = (
		{ name => cstring($client, "ARTISTS") . " (" . scalar @$artists . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::ArtistMenu::feed,
		  passthrough => [ $artists, { sortArtists => 1, sortAlbums => 1 } ] },
		{ name => cstring($client, "ALBUMS") . " (" . scalar @$albums . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::AlbumMenu::feed,
		  passthrough => [ $albums, { sortAlbums => 1 } ] },
		{ name => cstring($client, "SONGS") . " (" . scalar @$tracks . ")",
		  # TODO: actions for this playlist
		  type => 'playlist',
		  url => \&Plugins::GoogleMusic::TrackMenu::feed,
		  passthrough => [ $tracks, { showArtist => 1, showAlbum => 1, sortTracks => 1 } ], },
	);

	$callback->(\@menu);

	return;
}

sub search_all_access {
	my ($client, $callback, $args, $search, $opts) = @_;

	$args->{search} ||= $search;

	# The search string may be empty. We could forbid this.
	$args->{search} ||= '';

	my $result = Plugins::GoogleMusic::AllAccess::search($args->{search});

	if (!$result) {
		$callback->(errorMenu($client));
		return;
	}

	# Pass to artist/album/track menu when doing artist/album/track search
	if ($opts->{artistSearch}) {
		return Plugins::GoogleMusic::ArtistMenu::feed($client, $callback, $args, $result->{artists},
													  { all_access => 1 });
	}
	if ($opts->{albumSearch}) {
		return Plugins::GoogleMusic::AlbumMenu::feed($client, $callback, $args, $result->{albums},
													 { all_access => 1 });
	}
	if ($opts->{trackSearch}) {
		return Plugins::GoogleMusic::TrackMenu::feed($client, $callback, $args, $result->{tracks},
													 { all_access => 1, showArtist => 1, showAlbum => 1 });
	}

	# Do not add to recent searches when we are doing artist/album/track search
	Plugins::GoogleMusic::Recent::recentSearchesAdd($args->{search}) if $args->{search};

	my @menu = (
		{ name => cstring($client, "ARTISTS") . " (" . scalar @{$result->{artists}} . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::ArtistMenu::feed,
		  passthrough => [ $result->{artists}, { all_access => 1 } ], },
		{ name => cstring($client, "ALBUMS") . " (" . scalar @{$result->{albums}} . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::AlbumMenu::feed,
		  passthrough => [ $result->{albums}, { all_access => 1 } ], },
		{ name => cstring($client, "SONGS") . " (" . scalar @{$result->{tracks}} . ")",
		  # TODO: actions for this playlist
		  type => 'playlist',
		  url => \&Plugins::GoogleMusic::TrackMenu::feed,
		  passthrough => [ $result->{tracks}, { all_access => 1, showArtist => 1, showAlbum => 1 } ], },
	);

	$callback->(\@menu);

	return;
}

sub trackInfoMenu {
	my ($client, $url, $track, $remoteMeta) = @_;
	
	return unless $client;
	return unless $prefs->get('all_access_enabled');

	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;

	my @menu;
	my $item;

	if ($artist) {
		push @menu, {
			name        => cstring($client, 'ARTIST') . ": " . $artist,
			url         => \&search_all_access,
			passthrough => [ $artist, { artistSearch => 1 } ],
			type        => 'link',
			favorites   => 0,
		},
	};

	if ($album) {
		push @menu, {
			name        => cstring($client, 'ALBUM') . ": " . $album,
			url         => \&search_all_access,
			passthrough => [ $album, { albumSearch => 1 } ],
			type        => 'link',
			favorites   => 0,
		},
	};

	if ($track) {
		push @menu, {
			name        => cstring($client, 'TRACK') . ": " . $title,
			url         => \&search_all_access,
			passthrough => [ "$artist $title", { trackSearch => 1 } ],
			type        => 'link',
			favorites   => 0,
		},
	};

	if (scalar @menu) {
		$item = {
			name  => cstring($client, 'PLUGIN_GOOGLEMUSIC_ON_GOOGLEMUSIC'),
			items => \@menu,
		};
	}

	return $item;
}

sub searchInfoMenu {
	my ($client, $tags) = @_;

	# For some reason the search string gets encoded
	my $search = decode_utf8($tags->{search});

	# Always search in my music
	my @items = ({
		name        => cstring($client, 'PLUGIN_GOOGLEMUSIC_MY_MUSIC'),
		url         => \&search,
		passthrough => [ $search ],
	});

	# All Access is optional
	if ($prefs->get('all_access_enabled')) {
		push @items, {
			name        => cstring($client, 'PLUGIN_GOOGLEMUSIC_ALL_ACCESS'),
			url         => \&search_all_access,
			passthrough => [ $search ],
		};
	}

	return {
		name => cstring($client, 'PLUGIN_GOOGLEMUSIC'),
		items => \@items,
	};
}

<<<<<<< HEAD
sub itemQuery {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotQuery([['googlemusicbrowse'], ['items']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $uri = $request->getParam('uri');
	my $mode = $request->getParam('mode');
	my $command = $request->getRequest(0);

	my $feed = sub {
		my ($client, $callback, $args) = @_;
		if ($uri =~ /^googlemusic:album/) {
			my $album = Plugins::GoogleMusic::Library::get_album($uri);
			Plugins::GoogleMusic::AlbumMenu::_albumTracks($client, $callback, $args, $album, { playall => 1, playall_uri => $uri, sortByTrack => 1 });
		} elsif ($uri =~ /^googlemusic:artist/) {
			my $artist = Plugins::GoogleMusic::Library::get_artist($uri);
			Plugins::GoogleMusic::ArtistMenu::_artistMenu($client, $callback, $args, $artist, { mode => $mode });
		}
	};

	Slim::Control::XMLBrowser::cliQuery($command, $feed, $request);

	return;
}

sub playlistcontrolCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['googlemusicplaylistcontrol']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $cmd = $request->getParam('cmd');
	my $uri = $request->getParam('uri');
	my $jumpIndex = $request->getParam('play_index');

	if ($request->paramUndefinedOrNotOneOf($cmd, ['load', 'insert', 'add'])) {
		$request->setStatusBadParams();
		return;
	}

	my $load   = ($cmd eq 'load');
	my $insert = ($cmd eq 'insert');
	my $add    = ($cmd eq 'add');

	# if loading, first stop & clear everything
	if ($load) {
		Slim::Player::Playlist::stopAndClear($client);
	}

	# find the songs
	my @tracks = ();

	# info line and artwork to display if successful
	my $info;
	my $artwork;

	if ($uri =~ /^googlemusic:track/) {
		my $track = Plugins::GoogleMusic::Library::get_track($uri);
		if ($track) {
			$info = $track->{title} . " " . cstring($client, 'BY') . " " . $track->{artist}->{name};
			$artwork = $track->{cover};
			push @tracks, $track;
		}
	} elsif ($uri =~ /^googlemusic:album/) {
		my $album = Plugins::GoogleMusic::Library::get_album($uri);
		if ($album) {
			$info = $album->{name} . " " . cstring($client, 'BY') . " " . $album->{artist}->{name};
			$artwork = $album->{cover};
			push @tracks, @{$album->{tracks}};
		}
		# TODO: update recent albums AND recent artists
	} elsif ($uri =~ /^googlemusic:artist/) {
		# TODO: This has to be fixed for My Library
		my $artist = Plugins::GoogleMusic::AllAccess::get_artist_info($uri);
		if ($artist) {
			$info = cstring($client, "PLUGIN_GOOGLEMUSIC_TOP_TRACKS") . " " . cstring($client, 'BY') . " " . $artist->{name};
			$artwork = $artist->{image};
			push @tracks, @{$artist->{tracks}};
		}
		# TODO: update recent artists
	} else {
		$request->setStatusBadParams();
		return;
	}

	my @objs;

	for my $track (@tracks) {
		my $obj = Slim::Schema::RemoteTrack->updateOrCreate($track->{'uri'}, {
			title   => $track->{'title'},
			artist  => $track->{'artist'}->{'name'},
			album   => $track->{'album'}->{'name'},
			year    => $track->{'year'},
			secs    => $track->{'secs'},
			cover   => $track->{'cover'},
			tracknum=> $track->{'trackNumber'},
		});

		push @objs, $obj;
	}

	# don't call Xtracks if we got no songs
	if (@objs) {

		if ($load || $add || $insert) {
			my $token;
			my $showBriefly = 1;
			if ($add) {
				$token = 'JIVE_POPUP_ADDING';
			} elsif ($insert) {
				$token = 'JIVE_POPUP_TO_PLAY_NEXT';
			} else {
				$token = 'JIVE_POPUP_NOW_PLAYING';
				$showBriefly = undef;
			}
			# not to be shown for now playing, as we're pushing to now playing screen now and no need for showBriefly
			if ($showBriefly) {
				my $string = $client->string($token);
				$client->showBriefly({ 
					'jive' => { 
						'type'    => 'mixed',
						'style'   => 'add',
						'text'    => [ $string, $info ],
						'icon-id' => defined $artwork ? $artwork : '/html/images/cover.png',
					}
				});
			}

		}

		$cmd .= "tracks";

		$log->info("$cmd " . scalar @objs . " tracks" . ($jumpIndex ? " starting at $jumpIndex" : ""));

		Slim::Control::Request::executeRequest(
			$client, ['playlist', $cmd, 'listRef', \@objs, undef, $jumpIndex]
		);
	}

	$request->addResult('count', scalar(@objs));

	$request->setStatusDone();

	return;
}

sub errorMenu {
	my ($client) = @_;

	return [{
		name => cstring($client, 'PLUGIN_GOOGLEMUSIC_ERROR'),
		type => 'text',
	}];

}

1;
