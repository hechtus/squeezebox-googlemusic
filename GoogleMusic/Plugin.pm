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
	if (Plugins::GoogleMusic::GoogleAPI::get_version() lt '3.0.0') {
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

	Slim::Menu::GlobalSearch->registerInfoProvider( googlemusiclibrary => (
		after => 'middle',
		name  => 'PLUGIN_GOOGLEMUSIC',
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
		url => \&_tracks,
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
	my ($client, $callback, $args, $passthrough) = @_;

	$args->{search} ||= $passthrough->{search};

	# The search string may be empty. We could forbid this.
	my $search = $args->{'search'} || '';
	my @query = split(' ', $search);

	add_recent_search($search) if scalar @query;

	my ($tracks, $albums, $artists) = Plugins::GoogleMusic::Library::search({'any' => \@query});

	my @menu = (
		{ name => cstring($client, "ARTISTS") . " (" . scalar @$artists . ")",
		  type => 'link',
		  url => \&_artists,
		  passthrough => [ $artists, { sortArtists => 1, sortAlbums => 1 } ] },
		{ name => cstring($client, "ALBUMS") . " (" . scalar @$albums . ")",
		  type => 'link',
		  url => \&_albums,
		  passthrough => [ $albums, { sortAlbums => 1 } ] },
		{ name => cstring($client, "SONGS") . " (" . scalar @$tracks . ")",
		  type => 'playlist',
		  url => \&_tracks,
		  passthrough => [ $tracks, { showArtist => 1, showAlbum => 1, sortTracks => 1 } ], },
	);

	$callback->(\@menu);

	return;
}

sub search_all_access {
	my ($client, $callback, $args, $passthrough) = @_;

	$args->{search} ||= $passthrough->{search};

	# The search string may be empty. We could forbid this.
	my $search = $args->{'search'} || '';
	add_recent_search($search) if $search;

	my ($tracks, $albums, $artists) = Plugins::GoogleMusic::AllAccess::search($search);

	my @menu = (
		{ name => cstring($client, "ARTISTS") . " (" . scalar @$artists . ")",
		  type => 'link',
		  url => \&_artists,
		  passthrough => [ $artists, { all_access => 1, } ], },
		{ name => cstring($client, "ALBUMS") . " (" . scalar @$albums . ")",
		  type => 'link',
		  url => \&_albums,
		  passthrough => [ $albums, { all_access => 1, sortAlbums => 1 } ], },
		{ name => cstring($client, "SONGS") . " (" . scalar @$tracks . ")",
		  type => 'playlist',
		  url => \&_tracks,
		  passthrough => [ $tracks, { all_access => 1, showArtist => 1, showAlbum => 1 } ], },
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
			passthrough => [{
				search => $_
			}],
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

sub _show_track {

	my ($client, $track, $opts) = @_;

	# Show artist and/or album in name and line2
	my $showArtist = $opts->{'showArtist'};
	my $showAlbum = $opts->{'showAlbum'};

	# Play all tracks in a list or not when selecting. Useful for albums and playlists.
	my $playall = $opts->{'playall'};

	my $menu = {
		'name'     => $track->{title},
		'line1'    => $track->{title},
		'url'      => $track->{uri},
		'image'    => $track->{cover},
		'secs'     => $track->{secs},
		'duration' => $track->{secs},
		'bitrate'  => $track->{bitrate},
		'genre'    => $track->{genre},
		'type'     => 'audio',
		'play'     => $track->{uri},
		'playall'  => $playall,
	};

	if ($showArtist) {
		$menu->{'name'} .= " " . cstring($client, 'BY') . " " . $track->{artist}->{name};
		$menu->{'line2'} = $track->{artist}->{name};
	}

	if ($showAlbum) {
		$menu->{'name'} .= " \x{2022} " . $track->{album}->{name};
		if ($menu->{'line2'}) {
			$menu->{'line2'} .= " \x{2022} " . $track->{album}->{name};
		} else {
			$menu->{'line2'} = $track->{album}->{name};
		}
	}

	return $menu;
}

sub _tracks {
	my ($client, $callback, $args, $tracks, $opts) = @_;
	my $sortByTrack = $opts->{sortByTrack};
	my $sortTracks = $opts->{sortTracks};

	my @menu;

	if ($sortByTrack) {
		@$tracks = sort { ($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) or
						  ($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1)
		} @$tracks;
	} elsif ($sortTracks) {
		@$tracks = sort { lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) or
						 ($b->{year} || -1)  <=> ($a->{year} || -1) or
						 lc(($a->{name} || '')) cmp lc(($b->{name} || ''))  or
						 ($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) or
						 ($a->{trackNumber} || -1)  <=> ($b->{trackNumber} || -1)
		} @$tracks;
	}

	for my $track (@{$tracks}) {
		push @menu, _show_track($client, $track, $opts);
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

sub _tracks_for_album {
	my ($client, $callback, $args, $album, $opts) = @_;

	my $all_access = $opts->{'all_access'};
	my $tracks;

	# All Access or All Access album?
	if ($all_access || $album->{uri} =~ '^googlemusic:album:B') {
		my $info = Plugins::GoogleMusic::AllAccess::get_album_info($album->{uri});
		if ($info) {
			$tracks = $info->{tracks};
		} else {
			$tracks = [];
		}
	} else {
		$tracks = $album->{tracks};
	}

	_tracks($client, $callback, $args, $tracks, $opts);

	return;
}

sub _show_album {
	my ($client, $album, $opts) = @_;

	my $all_access = $opts->{'all_access'};

    my $albumYear = $album->{'year'} || " ? ";

	my $menu = {
		'name'  => $album->{'name'} . " (" . $albumYear . ")",
		'name2'  => $album->{'artist'}->{'name'},
		'line1' => $album->{'name'} . " (" . $albumYear . ")",
		'line2' => $album->{'artist'}->{'name'},
		'cover' => $album->{'cover'},
		'image' => $album->{'cover'},
		'type'  => 'playlist',
		'url'   => \&_tracks_for_album,
		'hasMetadata'   => 'album',
		'passthrough' => [ $album , { all_access => $all_access, playall => 1, sortByTrack => 1 } ],
		'albumInfo' => { info => { command => [ 'items' ], fixedParams => { uri => $album->{'uri'} } } },
		'albumData' => [
			{ type => 'link', label => 'ARTIST', name => $album->{'artist'}->{'name'}, url => 'anyurl',
		  },
			{ type => 'link', label => 'ALBUM', name => $album->{'name'} },
			{ type => 'link', label => 'YEAR', name => $album->{'year'} },
		],
	};

	return $menu;
}

sub _albums {
	my ($client, $callback, $args, $albums, $opts) = @_;
	my $sortAlbums = $opts->{sortAlbums};

	my @menu;

	if ($sortAlbums) {
		@$albums = sort { lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) or
						 ($b->{year} || -1) <=> ($a->{year} || -1) or
						  lc($a->{name}) cmp lc($b->{name})
		} @$albums;
	}

	for my $album (@{$albums}) {
		push @menu, _show_album($client, $album, $opts);
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

sub _show_menu_for_artist {
	my ($client, $callback, $args, $artist, $opts) = @_;
	my $sortAlbums = $opts->{sortAlbums};
	my $all_access = $opts->{all_access};

	my @menu;

	my $albums;

	if ($all_access) {
		my $artistId = $artist->{uri};
		my $info = Plugins::GoogleMusic::AllAccess::get_artist_info($artist->{uri});

		# TODO Error handling
		@menu = (
			{ name => cstring($client, "ALBUMS") . " (" . scalar @{$info->{albums}} . ")",
			  type => 'link',
			  url => \&_albums,
			  passthrough => [ $info->{albums}, $opts ], },
			{ name => cstring($client, "PLUGIN_GOOGLEMUSIC_TOP_TRACKS") . " (" . scalar @{$info->{tracks}} . ")",
			  type => 'link',
			  url => \&_tracks,
			  passthrough => [ $info->{tracks}, $opts ], },
			{ name => cstring($client, "PLUGIN_GOOGLEMUSIC_RELATED_ARTISTS") . " (" . scalar @{$info->{related}} . ")",
			  type => 'link',
			  url => \&_artists,
			  passthrough => [ $info->{related}, $opts ], },
		);

	} else {
		my ($tracks, $artists);
		($tracks, $albums, $artists) = Plugins::GoogleMusic::Library::find_exact({'artist' => $artist->{'name'}});

		if ($sortAlbums) {
			@$albums = sort { lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) or
							 ($b->{year} || -1) <=> ($a->{year} || -1) or
							  lc($a->{name}) cmp lc($b->{name})
			} @$albums;
		}

		for my $album (@{$albums}) {
			push @menu, _show_album($client, $album, $opts);
		}
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

sub _show_artist {
	my ($client, $artist, $opts) = @_;

	my $menu;

	$menu = {
		name => $artist->{'name'},
		image => $artist->{'image'},
		type => 'link',
		url => \&_show_menu_for_artist,
		passthrough => [ $artist, $opts ],
	};

	return $menu;
}

sub _artists {
	my ($client, $callback, $args, $artists, $opts) = @_;
	my $sortArtists = $opts->{sortArtists};

	my @menu;

	if ($sortArtists) {
		@$artists = sort { lc($a->{name}) cmp lc($b->{name}) } @$artists;
	}

	for my $artist (@{$artists}) {
		push @menu, _show_artist($client, $artist, $opts);
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

sub searchInfoMenu {
	my ($client, $tags) = @_;

	# For some reason the search string gets encoded
	my $query = decode_utf8($tags->{'search'});

	return {
		name => cstring($client, 'PLUGIN_GOOGLEMUSIC'),
		items => [{
			name        => cstring($client, 'PLUGIN_GOOGLEMUSIC_MY_MUSIC'),
			url         => \&search,
			passthrough => [{ search => $query },],
		},{
			name        => cstring($client, 'PLUGIN_GOOGLEMUSIC_ALL_ACCESS'),
			url         => \&search_all_access,
			passthrough => [{ search => $query },],
		}],
	};
}

1;
