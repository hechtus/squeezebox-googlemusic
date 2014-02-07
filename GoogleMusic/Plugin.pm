package Plugins::GoogleMusic::Plugin;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;
use base qw(Slim::Plugin::OPMLBased);

use Encode qw(decode_utf8);

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
use Plugins::GoogleMusic::TrackMenu;
use Plugins::GoogleMusic::AlbumMenu;
use Plugins::GoogleMusic::ArtistMenu;

# TODO: move these constants to the configurable settings?
# Note: these constants can't be passed to the python API
use Readonly;
Readonly my $MAX_RECENT_ITEMS => 50;
Readonly my $RECENT_CACHE_TTL => 'never';

my %recent_searches;
tie %recent_searches, 'Tie::Cache::LRU', $MAX_RECENT_ITEMS;

my $cache = Slim::Utils::Cache->new('googlemusic', 3);

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

	# initialize recent searches: need to add them to the LRU cache ordered by timestamp
	my $recent_searches = $cache->get('recent_searches');
	map {
		$recent_searches{$_} = $recent_searches->{$_};
	} sort {
		$recent_searches->{$a}->{ts} <=> $recent_searches->{$a}->{ts}
	} keys %$recent_searches;



	if (!$googleapi->login($prefs->get('username'),
						   $prefs->get('password'))) {
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

	return;
}

sub shutdownPlugin {
	$googleapi->logout();

	return;
}


sub badVersion {
	my ($client, $callback, $args) = @_;

	my @menu;
	push @menu, {
		name => cstring($client, 'PLUGIN_GOOGLEMUSIC_BAD_VERSION'),
		type => 'text',
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
		{ name => cstring($client, 'PLAYLISTS'), type => 'link', url => \&_playlists },
		{ name => cstring($client, 'SEARCH'), type => 'search', url => \&search },
		{ name => cstring($client, 'RECENT_SEARCHES'), type => 'link', url => \&recent_searches, passthrough => [{ "all_access" => 0 },] },
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
		{ name => cstring($client, 'RECENT_SEARCHES'), type => 'link', url => \&recent_searches, passthrough => [{ "all_access" => 1 },] },
	);

	$callback->(\@menu);

	return;
}

sub _show_playlist {
	my ($client, $playlist) = @_;

	my $menu;

	$menu = {
		name => $playlist->{'name'},
		type => 'playlist',
		url => \&Plugins::GoogleMusic::TrackMenu::menu,
		passthrough => [$playlist->{tracks}, { showArtist => 1, showAlbum => 1, playall => 1 }],
	};

	return $menu;
}

sub _playlists {
	my ($client, $callback, $args) = @_;

	my @menu;

	my $playlists = Plugins::GoogleMusic::Playlists->get();

	for my $playlist (@{$playlists}) {
		push @menu, _show_playlist($client, $playlist);
	}

	if (!scalar @menu) {
		push @menu, {
			'name' => cstring($client, 'EMPTY'),
			'type' => 'text',
		}

	}

	$callback->(\@menu);

	return;
}

sub search {
	my ($client, $callback, $args, $search) = @_;

	$args->{search} ||= $search;

	# The search string may be empty. We could forbid this.
	$args->{search} ||= '';
	my @query = split(' ', $args->{search});

	add_recent_search($args->{search}) if scalar @query;

	my ($tracks, $albums, $artists) = Plugins::GoogleMusic::Library::search({'any' => \@query});

	my @menu = (
		{ name => cstring($client, "ARTISTS") . " (" . scalar @$artists . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::ArtistMenu::menu,
		  passthrough => [ $artists, { sortArtists => 1, sortAlbums => 1 } ] },
		{ name => cstring($client, "ALBUMS") . " (" . scalar @$albums . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::AlbumMenu::menu,
		  passthrough => [ $albums, { sortAlbums => 1 } ] },
		{ name => cstring($client, "SONGS") . " (" . scalar @$tracks . ")",
		  type => 'playlist',
		  url => \&Plugins::GoogleMusic::TrackMenu::menu,
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

	# Pass to artist/album/track menu when doing artist/album/track search
	if ($opts->{artistSearch}) {
		return Plugins::GoogleMusic::ArtistMenu::menu($client, $callback, $args, $result->{artists},
													  { all_access => 1 });
	}
	if ($opts->{albumSearch}) {
		return Plugins::GoogleMusic::AlbumMenu::menu($client, $callback, $args, $result->{albums},
													 { all_access => 1 });
	}
	if ($opts->{trackSearch}) {
		return Plugins::GoogleMusic::TrackMenu::menu($client, $callback, $args, $result->{tracks},
													 { all_access => 1, showArtist => 1, showAlbum => 1 });
	}

	# Do not add to recent searches when we are doing artist/album/track search
	add_recent_search($search) if $args->{search};

	my @menu = (
		{ name => cstring($client, "ARTISTS") . " (" . scalar @{$result->{artists}} . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::ArtistMenu::menu,
		  passthrough => [ $result->{artists}, { all_access => 1 } ], },
		{ name => cstring($client, "ALBUMS") . " (" . scalar @{$result->{albums}} . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::AlbumMenu::menu,
		  passthrough => [ $result->{albums}, { all_access => 1 } ], },
		{ name => cstring($client, "SONGS") . " (" . scalar @{$result->{tracks}} . ")",
		  type => 'playlist',
		  url => \&Plugins::GoogleMusic::TrackMenu::menu,
		  passthrough => [ $result->{tracks}, { all_access => 1, showArtist => 1, showAlbum => 1 } ], },
	);

	$callback->(\@menu);

	return;
}


sub add_recent_search {
	my $search = shift;

	return unless $search;

	$recent_searches{$search} = {
		ts => time(),
	};

	$cache->set('recent_searches', \%recent_searches, $RECENT_CACHE_TTL);

	return;
}

sub recent_searches {
	my ($client, $callback, $args, $opts) = @_;

	my $all_access = $opts->{'all_access'};

	my $recent = [
		sort { lc($a) cmp lc($b) }
		grep { $recent_searches{$_} }
		keys %recent_searches
	];

	my $search_func = $all_access ? \&search_all_access : \&search;
	my $items = [];

	foreach (@$recent) {
		push @$items, {
			type => 'link',
			name => $_,
			url  => $search_func,
			passthrough => [ $_ ],
		}
	}

	$items = [ {
		name => cstring($client, 'EMPTY'),
		type => 'text',
	} ] if !scalar @$items;

	$callback->({
		items => $items
	});

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
			type        => 'playlist',
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

	return {
		name => cstring($client, 'PLUGIN_GOOGLEMUSIC'),
		items => [{
			name        => cstring($client, 'PLUGIN_GOOGLEMUSIC_MY_MUSIC'),
			url         => \&search,
			passthrough => [ $search ],
		},{
			name        => cstring($client, 'PLUGIN_GOOGLEMUSIC_ALL_ACCESS'),
			url         => \&search_all_access,
			passthrough => [ $search ],
		}],
	};
}

1;
