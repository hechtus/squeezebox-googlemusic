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

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.googlemusic',
	'defaultLevel' => 'INFO',
#	'defaultLevel' => 'DEBUG',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.googlemusic');

sub getDisplayName {
	return 'PLUGIN_GOOGLEMUSIC';
}

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

	my $search = $args->{'search'};

	my $result = $googleapi->search({'any' => $search});

	my @menu = (
		{ name => "Tracks (" . scalar @$result . ")",
		  type => 'link',
		  url => \&trackbrowse,
		  passthrough => [ $result ] },
	);

	$callback->(\@menu);
}


sub trackbrowse {

	my ($client, $callback, $args, $tracks) = @_;

	my @tracksmenu;

	for my $track (@{$tracks}) {
		push @tracksmenu, {
			'name'     => $track->{'name'}. " " . string('BY') . " " . $track->{'artist'},
			'line1'    => $track->{'name'},
			'line2'    => $track->{'artist'},
			'url'      => "googlemusic:" . $track->{'id'},
			'icon'     => $track->{'albumArt'},
			'type'     => 'audio',
			'passthrough' => [ $tracks ],
			'play'     => "googlemusic:" . $track->{'id'},
			#'hasMetadata' => 'track',
			#'itemActions' => $class->actions({ info => 1, play => 1, uri => $track->{'uri'} }),			
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

1;

__END__
