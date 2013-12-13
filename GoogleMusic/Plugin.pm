package Plugins::GoogleMusic::Plugin;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;
use base qw(Slim::Plugin::OPMLBased);

use Plugins::GoogleMusic::Settings;
use Scalar::Util qw(blessed);
use Slim::Control::Request;
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(string);

use Plugins::GoogleMusic::GoogleAPI;
use Plugins::GoogleMusic::ProtocolHandler;
use Plugins::GoogleMusic::Image;
use Plugins::GoogleMusic::Library;

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
		'description'  => string('PLUGIN_GOOGLEMUSIC'),
	});
}

sub getDisplayName {
	return 'PLUGIN_GOOGLEMUSIC';
}

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		tag    => 'googlemusic',
		feed   => \&toplevel,
		is_app => 1,
		weight => 1,
	);

	if (main::WEBUI) {
		Plugins::GoogleMusic::Settings->new;
	}

	Slim::Web::Pages->addRawFunction('/googlemusicimage', \&Plugins::GoogleMusic::Image::handler);

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
	}

	return;
}

sub shutdownPlugin {
	$googleapi->logout();

	return;
}

sub toplevel {
	my ($client, $callback, $args) = @_;

	my @menu;

	if ($prefs->get('all_access_enabled')) {
		@menu = (
			{ name => string('PLUGIN_GOOGLEMUSIC_MY_MUSIC'), type => 'link', url => \&my_music },
			{ name => string('PLUGIN_GOOGLEMUSIC_ALL_ACCESS'), type => 'link', url => \&all_access },
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
		{ name => string('PLUGIN_GOOGLEMUSIC_BROWSE'), type => 'link', url => \&search },
		{ name => string('PLAYLISTS'), type => 'link', url => \&_playlists },
		{ name => string('SEARCH'), type => 'search', url => \&search },
		{ name => string('RECENT_SEARCHES'), type => 'link', url => \&recent_searches, passthrough => [{ "all_access" => 0 },] },
		{ name => string('PLUGIN_GOOGLEMUSIC_RELOAD_LIBRARY'), type => 'func', url => \&reload_library },
	);

	$callback->(\@menu);

	return;
}

sub reload_library {
	my ($client, $callback, $args) = @_;

	Plugins::GoogleMusic::Library::refresh();

	my @menu;
	push @menu, {
		'name' => string('PLUGIN_GOOGLEMUSIC_LIBRARY_RELOADED'),
		'type' => 'text',
	};

	$callback->(\@menu);

	return;
}

sub all_access {
	my ($client, $callback, $args) = @_;
	my @menu = (
		{ name => string('SEARCH'), type => 'search', url => \&search_all_access },
		{ name => string('RECENT_SEARCHES'), type => 'link', url => \&recent_searches, passthrough => [{ "all_access" => 1 },] },
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

	my $playlists = $googleapi->get_playlists();

	for my $playlist (@{$playlists}) {
		push @menu, _show_playlist($client, $playlist);
	}

	if (!scalar @menu) {
		push @menu, {
			'name' => string('EMPTY'),
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
		{ name => string("ARTISTS") . " (" . scalar @$artists . ")",
		  type => 'link',
		  url => \&_artists,
		  passthrough => [ $artists, { sortArtists => 1, sortAlbums => 1 } ] },
		{ name => string("ALBUMS") . " (" . scalar @$albums . ")",
		  type => 'link',
		  url => \&_albums,
		  passthrough => [ $albums, { sortAlbums => 1 } ] },
		{ name => string("SONGS") . " (" . scalar @$tracks . ")",
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

	my ($tracks, $albums, $artists) = $googleapi->search_all_access($search);

	my @menu = (
		{ name => string("ARTISTS") . " (" . scalar @$artists . ")",
		  type => 'link',
		  url => \&_artists,
		  passthrough => [ $artists, { all_access => 1, } ], },
		{ name => string("ALBUMS") . " (" . scalar @$albums . ")",
		  type => 'link',
		  url => \&_albums,
		  passthrough => [ $albums, { all_access => 1, sortAlbums => 1 } ], },
		{ name => string("SONGS") . " (" . scalar @$tracks . ")",
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
		name => string('EMPTY'),
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
		$menu->{'name'} .= " " . string('BY') . " " . $track->{artist};
		$menu->{'line2'} = $track->{artist};
	}

	if ($showAlbum) {
		$menu->{'name'} .= " \x{2022} " . $track->{album};
		if ($menu->{'line2'}) {
			$menu->{'line2'} .= " \x{2022} " . $track->{album};
		} else {
			$menu->{'line2'} = $track->{album};
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
		@$tracks = sort { lc($a->{artist}) cmp lc($b->{artist}) or
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
			'name' => string('EMPTY'),
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

	# all_access is either forced by parameter or by album uri pattern 
	my ($all_access_albumid) = $album->{'uri'} =~ m{^googlemusic:all_access_album:(.*)$}x;
	if (!$all_access_albumid && $all_access) {
		$all_access_albumid = $album->{'albumId'};
	}

	if ($all_access_albumid) {
		my $info = $googleapi->get_album_info($all_access_albumid);
		$tracks = $info->{'tracks'};
	} else {
		my ($albums, $artists);
		($tracks, $albums, $artists) = Plugins::GoogleMusic::Library::find_exact({'album_uri' => $album->{'uri'}});
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
		'name2'  => $album->{'artist'},
		'line1' => $album->{'name'} . " (" . $albumYear . ")",
		'line2' => $album->{'artist'},
		'cover' => $album->{'cover'},
		'image' => $album->{'cover'},
		'type'  => 'playlist',
		'url'   => \&_tracks_for_album,
		'hasMetadata'   => 'album',
		'passthrough' => [ $album , { all_access => $all_access, playall => 1, sortByTrack => 1 } ],
		'albumInfo' => { info => { command => [ 'items' ], fixedParams => { uri => $album->{'uri'} } } },
		'albumData' => [
			{ type => 'link', label => 'ARTIST', name => $album->{'artist'}, url => 'anyurl',
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
		@$albums = sort { lc($a->{artist}) cmp lc($b->{artist}) or
						 ($b->{year} || -1) <=> ($a->{year} || -1) or
						  lc($a->{name}) cmp lc($b->{name})
		} @$albums;
	}

	for my $album (@{$albums}) {
		push @menu, _show_album($client, $album, $opts);
	}

	if (!scalar @menu) {
		push @menu, {
			'name' => string('EMPTY'),
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
		my ($toptracks, $related_artists);
		my $artistId = $artist->{'artistId'};
		($toptracks, $albums, $related_artists) = $googleapi->get_artist_info($artistId);

		@menu = (
			{ name => string("ALBUMS") . " (" . scalar @$albums . ")",
			  type => 'link',
			  url => \&_albums,
			  passthrough => [ $albums, $opts ], },
			{ name => string("PLUGIN_GOOGLEMUSIC_TOP_TRACKS") . " (" . scalar @$toptracks . ")",
			  type => 'link',
			  url => \&_tracks,
			  passthrough => [ $toptracks, $opts ], },
			{ name => string("PLUGIN_GOOGLEMUSIC_RELATED_ARTISTS") . " (" . scalar @$related_artists . ")",
			  type => 'link',
			  url => \&_artists,
			  passthrough => [ $related_artists, $opts ], },
		);

	} else {
		my ($tracks, $artists);
		($tracks, $albums, $artists) = Plugins::GoogleMusic::Library::find_exact({'artist' => $artist->{'name'}});

		if ($sortAlbums) {
			@$albums = sort { lc($a->{artist}) cmp lc($b->{artist}) or
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
			'name' => string('EMPTY'),
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
			'name' => string('EMPTY'),
			'type' => 'text',
		}
	}

	$callback->(\@menu);

	return;
}


1;
