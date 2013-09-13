package Plugins::GoogleMusic::Plugin;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
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

use constant MAX_RECENT_ITEMS => 50;
use constant RECENT_CACHE_TTL => 'never';

my %recent_searches;
tie %recent_searches, 'Tie::Cache::LRU', MAX_RECENT_ITEMS;

my $cache = Slim::Utils::Cache->new('googlemusic', 3);

my $log;
my $prefs = preferences('plugin.googlemusic');

BEGIN {
	$log = Slim::Utils::Log->addLogCategory({
		'category'     => 'plugin.googlemusic',
		'defaultLevel' => 'WARN',
		'description'  => string('PLUGIN_GOOGLEMUSIC'),
	});
}

sub getDisplayName { 'PLUGIN_GOOGLEMUSIC' }

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
	}
}

sub shutdownPlugin {
	$googleapi->logout();
}

sub toplevel {
	my ($client, $callback, $args) = @_;

	my @menu = (
		{ name => string('PLUGIN_GOOGLEMUSIC_MY_LIBRARY'), type => 'link', url => \&search },
		{ name => string('PLUGIN_GOOGLEMUSIC_PLAYLISTS'), type => 'link', url => \&playlists },
		{ name => string('PLUGIN_GOOGLEMUSIC_SEARCH'), type => 'search', url => \&search },
		{ name => string('PLUGIN_GOOGLEMUSIC_RECENT_SEARCHES'), type => 'link', url => \&recent_searches },
	);

	$callback->(\@menu);
}

sub playlists {
	my ($client, $callback, $args) = @_;

	my @menu;

	my $playlists = $googleapi->get_all_playlist_contents();

	for my $playlist (@{$playlists}) {
		push @menu, playlist($client, $playlist);
	}

	if (!scalar @menu) {
		push @menu, {
			'name'     => string('PLUGIN_GOOGLEMUSIC_NO_SEARCH_RESULTS'),
			'type'     => 'text',
		}

	}

	$callback->(\@menu);
}

sub playlist {

	my ($client, $playlist) = @_;

	my @tracks;

	for my $playlist_track (@{$playlist->{'tracks'}}) {
		my $track = $googleapi->get_track_by_id($playlist_track->{'trackId'});
		if ($track) {
			push @tracks, $track;
		}
	}

	my $menu = {
		'name'        => $playlist->{'name'},
		'type'        => 'playlist',
		'url'         => \&_tracks,
		'passthrough' => [\@tracks, { showArtist => 1, showAlbum => 1, playall => 1 }],
	};

	return $menu;
}

sub search {
	my ($client, $callback, $args, $passthrough) = @_;

	$args->{search} ||= $passthrough->{search};

	# The search string may be empty. We could forbid this.
	my $search = $args->{'search'} || '';
	my @query = split(' ', $search);

	add_recent_search($search) if scalar @query;

	my ($tracks, $albums, $artists) = $googleapi->search({'any' => \@query});

	my @menu = (
		{ name => "Artists (" . scalar @$artists . ")",
		  type => 'link',
		  url => \&_artists,
		  passthrough => [ $artists ] },
		{ name => "Albums (" . scalar @$albums . ")",
		  type => 'link',
		  url => \&_albums,
		  passthrough => [ $albums ] },
		{ name => "Tracks (" . scalar @$tracks . ")",
		  type => 'playlist',
		  url => \&_tracks,
		  passthrough => [ $tracks , { showArtist => 1, showAlbum => 1 } ], },
	);

	$callback->(\@menu);
}


sub add_recent_search {
	my $search = shift;
	
	return unless $search;
	
	$recent_searches{$search} = {
		ts => time(),
	};
	
	$cache->set('recent_searches', \%recent_searches, RECENT_CACHE_TTL);
}

sub recent_searches {
	my ($client, $callback, $args) = @_;

	my $recent = [ 
		sort { lc($a) cmp lc($b) } 
		grep { $recent_searches{$_} }
		keys %recent_searches 
	];
	
	my $items = [];
	
	foreach (@$recent) {
		push @$items, {
			type => 'link',
			name => $_,
			url  => \&search,
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
}

sub _show_track {

	my ($client, $track, $opts) = @_;

	# Show artist and/or album in name and line2
	my $showArtist = $opts->{'showArtist'};
	my $showAlbum = $opts->{'showAlbum'};
	# Play all tracks in a list or not when selecting. Useful for albums and playlists.
	my $playall = $opts->{'playall'};

	my $secs = $track->{'durationMillis'} / 1000;

	my $menu = {
		'name'     => $track->{'title'},
		'line1'    => $track->{'title'},
		'url'      => $track->{'uri'},
		'image'    => Plugins::GoogleMusic::Image->uri($track->{'albumArtUrl'}),
		'secs'     => $secs,
		'duration' => $secs,
		'bitrate'  => 320,
		'genre'    => $track->{'genre'},
		'_disc'    => $track->{'discNumber'},
		'_track'   => $track->{'trackNumber'},
		'type'     => 'audio',
		'play'     => $track->{'uri'},
		'playall'  => $playall,
	};

	if ($showArtist) {
		$menu->{'name'} .= " " . string('BY') . " " . $track->{'artist'};
		$menu->{'line2'} = $track->{'artist'};
	}

	if ($showAlbum) {
		$menu->{'name'} .= " \x{2022} " . $track->{'album'};
		if ($menu->{'line2'}) {
			$menu->{'line2'} .= " \x{2022} " . $track->{'album'};
		} else {
			$menu->{'line2'} = $track->{'album'};
		}
	}

	return $menu;

}

sub _show_tracks {
	my ($client, $tracks, $opts) = @_;
	my $sortByTrack = $opts->{'sortByTrack'};

	my @menu;

	for my $track (@{$tracks}) {
		push @menu, _show_track($client, $track, $opts);
	}

	if ($sortByTrack) {
		@menu = sort { $a->{_disc} <=> $b->{_disc} || $a->{_track} <=> $b->{_track} } @menu;
	}

	if (!scalar @menu) {
		push @menu, {
			'name' => string('EMPTY'),
			'type' => 'text',
		}
	}
	
	return \@menu;
}

sub _tracks {

	my ($client, $callback, $args, $tracks, $opts) = @_;

	$callback->(_show_tracks($client, $tracks, $opts));
}

sub _show_album {
	my ($client, $album, $opts) = @_;

	my ($tracks, $albums, $artists) = $googleapi->search({'artist' => $album->{'artist'},
														  'album' => $album->{'name'},
														  'year' => $album->{'year'}});

	my $menu = {
		'name'  => $album->{'name'},
		'name2'  => $album->{'artist'},
		'line1' => $album->{'name'},
		'line2' => $album->{'artist'},
		'cover' => Plugins::GoogleMusic::Image->uri($album->{'albumArtUrl'}),
		'image' => Plugins::GoogleMusic::Image->uri($album->{'albumArtUrl'}),
		'type'  => 'playlist',
		'url'   => \&_tracks,
		'hasMetadata'   => 'album',
		'passthrough' => [ $tracks , { playall => 1, sortByTrack => 1 } ],
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

sub _show_albums {
	my ($client, $albums, $opts) = @_;

	my @menu;

	for my $album (@{$albums}) {
		push @menu, _show_album($client, $album, $opts);
	}

	if (!scalar @menu) {
		push @menu, {
			'name' => string('EMPTY'),
			'type' => 'text',
		}
	}
	
	return \@menu;
}

sub _albums {
	my ($client, $callback, $args, $albums, $opts) = @_;

	$callback->(_show_albums($client, $albums, $opts));
}

sub _show_artist {
	my ($client, $artist, $opts) = @_;

	my ($tracks, $albums, $artists) = $googleapi->search({'artist' => $artist->{'name'}});

	my $menu = {
		name  => $artist->{'name'},
		image => Plugins::GoogleMusic::Image->uri($artist->{'artistImageBaseUrl'}),
		items => _show_albums($client, $albums),
	};
	
	return $menu;
}

sub _show_artists {
	my ($client, $artists, $opts) = @_;

	my @menu;

	for my $artist (@{$artists}) {
		push @menu, _show_artist($client, $artist, $opts);
	}

	if (!scalar @menu) {
		push @menu, {
			'name' => string('EMPTY'),
			'type' => 'text',
		}
	}
	
	return \@menu;
}

sub _artists {
	my ($client, $callback, $args, $artists, $opts) = @_;

	$callback->(_show_artists($client, $artists, $opts));
}


1;

__END__
