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
		'defaultLevel' => 'INFO',
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
		menu   => 'radios',
		weight => 1,
	);

	if (main::WEBUI) {
		Plugins::GoogleMusic::Settings->new;
	}

	Slim::Web::Pages->addRawFunction('/googlemusicimage', \&Plugins::GoogleMusic::Image::handler);

	$googleapi->login($prefs->get('username'),
					  $prefs->get('password'));
}

sub shutdownPlugin {
	$googleapi->logout();
}

sub toplevel {
	my ($client, $callback, $args) = @_;

	my @menu = (
		{ name => string('PLUGIN_GOOGLEMUSIC_PLAYLISTS'), type => 'link', url => \&sublevel, passthrough => [ 'Playlists' ] },
		{ name => string('PLUGIN_GOOGLEMUSIC_RECENT_SEARCHES'), type => 'link', url => \&sublevel, passthrough => [ 'searches' ] },
		{ name => string('PLUGIN_GOOGLEMUSIC_SEARCH'), type => 'search', url => \&search },
	);

	$callback->(\@menu);
}

sub sublevel {

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
		  type => 'link',
		  url => \&trackbrowse,
		  passthrough => [ $tracks ] },
	);

	$callback->(\@menu);
}


sub trackbrowse {

	my ($client, $callback, $args, $tracks) = @_;

	my @tracksmenu;

	for my $track (@{$tracks}) {
		my $secs = $track->{'durationMillis'} / 1000;
		push @tracksmenu, {
			'artist'   => $track->{'artist'},
			'year'     => $track->{'year'},
			'name'     => $track->{'name'}. " " . string('BY') . " " . $track->{'artist'},
			'line1'    => $track->{'name'},
			'line2'    => $track->{'artist'} . " \x{2022} " . $track->{'album'},
			'url'      => $track->{'uri'},
			'uri'      => $track->{'uri'},
			'image'    => Plugins::GoogleMusic::Image->uri($track->{'albumArtUrl'}),
			'secs'     => $secs,
			'duration' => sprintf('%d:%02d', int($secs / 60), $secs % 60),
			'type'     => 'audio',
			'play'     => $track->{'uri'},
		}
	}

	if (!scalar @tracksmenu) {
		push @tracksmenu, {
			'name'     => string('PLUGIN_GOOGLEMUSIC_NO_SEARCH_RESULTS'),
			'type'     => 'text',
		}

	}
	
	$callback->(\@tracksmenu);
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

	for my $track (@{$tracks}) {
		my $secs = $track->{'durationMillis'} / 1000;
		push @tracksmenu, {
			'name'     => $track->{'name'},
			'line1'    => $track->{'name'},
			'line2'    => $track->{'artist'} . " \x{2022} " . $track->{'album'},
			'url'      => $track->{'uri'},
			'image'    => Plugins::GoogleMusic::Image->uri($track->{'albumArtUrl'}),
			'secs'     => $secs,
			'duration' => sprintf('%d:%02d', int($secs / 60), $secs % 60),
			'type'     => 'audio',
			'_disc'    => $track->{'disc'},
			'_track'   => $track->{'track'},
			'passthrough' => [ $track ],
			'play'     => $track->{'uri'},
			#'hasMetadata' => 'album',
			#'itemActions' => $class->actions({ info => 1, play => 1, uri => $track->{'uri'} }),			
		}
	}

	@tracksmenu = sort { $a->{_disc} != $b->{_disc} ? $a->{_disc} <=> $b->{_disc} : $a->{_track} <=> $b->{_track} } @tracksmenu;

	%menu = (
		'name'  => $album->{'name'},
		'cover' => Plugins::GoogleMusic::Image->uri($album->{'albumArtUrl'}),
		'image' => Plugins::GoogleMusic::Image->uri($album->{'albumArtUrl'}),
		'type'     => 'playlist',
		'items' => \@tracksmenu,
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
			'url'      => $artist->{'uri'},
			'image'    => Plugins::GoogleMusic::Image->uri($artist->{'artistImageBaseUrl'}),
			'type'     => 'playlist',
			'passthrough' => [ $artists ],
			'play'     => $artist->{'uri'},
			#'hasMetadata' => 'track',
			#'itemActions' => $class->actions({ info => 1, play => 1, uri => $track->{'uri'} }),			
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

1;

__END__
