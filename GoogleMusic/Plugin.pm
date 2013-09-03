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
		{ name => string('PLUGIN_GOOGLEMUSIC_PLAYLISTS'), type => 'link', url => \&playlists },
		{ name => string('PLUGIN_GOOGLEMUSIC_RECENT_SEARCHES'), type => 'link', url => \&recent_searches },
		{ name => string('PLUGIN_GOOGLEMUSIC_SEARCH'), type => 'search', url => \&search },
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


sub recent_searches {
	my ($client, $callback, $args) = @_;

	my @menu = (
		{ name => "To be implemented.",
		  type => 'text',
		}
	);

	$callback->(\@menu);
}

sub search {
	my ($client, $callback, $args) = @_;

	# The search string may be empty. We could forbid this.
	my $search = $args->{'search'} || '';
	my @query = split(' ', $search);

	my ($tracks, $albums, $artists) = $googleapi->search({'any' => \@query});

	my @menu = (
		{ name => "Artists (" . scalar @$artists . ")",
		  type => 'link',
		  url => \&artistbrowse,
		  passthrough => [ $artists ] },
		{ name => "Albums (" . scalar @$albums . ")",
		  type => 'link',
		  url => \&albumbrowse,
		  passthrough => [ $albums ] },
		{ name => "Tracks (" . scalar @$tracks . ")",
		  type => 'playlist',
		  url => \&_tracks,
		  passthrough => [ $tracks , { showArtist => 1, showAlbum => 1 } ], },
	);

	$callback->(\@menu);
}

sub albumbrowse {

	my ($client, $callback, $args, $albums) = @_;

	my @menu;

	for my $album (@{$albums}) {
		push @menu, album($client, $album);
	}

	if (!scalar @menu) {
		push @menu, {
			'name'     => string('PLUGIN_GOOGLEMUSIC_NO_SEARCH_RESULTS'),
			'type'     => 'text',
		}

	}
	
	$callback->(\@menu);
}

sub album {

	my ($client, $album) = @_;

	my %menu;
	my @tracksmenu;

	my ($tracks, $albums, $artists) = $googleapi->search({'artist' => $album->{'artist'},
														  'album' => $album->{'name'},
														  'year' => $album->{'year'}});

	%menu = (
		'name'  => $album->{'name'},
		'line1' => $album->{'name'},
		'line2' => $album->{'artist'},
		'cover' => Plugins::GoogleMusic::Image->uri($album->{'albumArtUrl'}),
		'image' => Plugins::GoogleMusic::Image->uri($album->{'albumArtUrl'}),
		'type'  => 'playlist',
		'url'   => \&_tracks,
		'passthrough' => [ $tracks , { playall => 1, sortByTrack => 1 } ],
		'albumInfo' => { info => { command => [ 'items' ], fixedParams => { uri => $album->{'uri'} } } },
		'albumData' => [
			{ type => 'link', label => 'ARTIST', name => $album->{'artist'}, url => 'anyurl',
		  },
			{ type => 'link', label => 'ALBUM', name => $album->{'name'} },
			{ type => 'link', label => 'YEAR', name => $album->{'year'} },
		],
	);

	return \%menu;
}

sub artistbrowse {

	my ($client, $callback, $args, $artists) = @_;

	my @menu;

	for my $artist (@{$artists}) {
		push @menu, {
			'name'     => $artist->{'name'},
			'line1'    => $artist->{'name'},
			'url'      => \&artist,
			'image'    => Plugins::GoogleMusic::Image->uri($artist->{'artistImageBaseUrl'}),
			'type'     => 'playlist',
			'passthrough' => [ $artists ],
			'play'     => $artist->{'uri'},
		}
	}

	if (!scalar @menu) {
		push @menu, {
			'name'     => string('PLUGIN_GOOGLEMUSIC_NO_SEARCH_RESULTS'),
			'type'     => 'text',
		}

	}
	
	$callback->(\@menu);
}

sub artist {
	my ($client, $callback, $args) = @_;

	my @menu = (
		{ name => "To be implemented.",
		  type => 'text',
		}
	);

	$callback->(\@menu);
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
		'duration' => sprintf('%d:%02d', int($secs / 60), $secs % 60),
		'_disc'    => $track->{'discNumber'},
		'_track'   => $track->{'trackNumber'},
		'fs'       => $track->{'estimatedSize'},
		'filesize' => $track->{'estimatedSize'},
		'type'     => 'audio',
		'play'     => $track->{'uri'},
		'playall'  => $playall,
		'itemActions' => { info => { command => [ "trackinfo", 'items' ], fixedParams => {url => $track->{'uri'}} } },
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

1;

__END__
