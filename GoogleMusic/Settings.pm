package Plugins::GoogleMusic::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Prefs;

use Plugins::GoogleMusic::GoogleAPI;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

$prefs->init({
	max_search_items => 100,
	max_artist_tracks => 25,
	max_related_artists => 10,
});

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_GOOGLEMUSIC');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/GoogleMusic/settings/basic.html');
}

sub handler {
	my ($class, $client, $params) = @_;

	if (!$googleapi->is_authenticated()) {
		$params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_NOT_LOGGED_IN');
	}

	if ($params->{'saveSettings'} && $params->{'username'} && $params->{'password'}) {
		$prefs->set('username', $params->{'username'});
		$prefs->set('password', $params->{'password'});

		# Logout from Google
		$googleapi->logout();
		# Now try to login with new username/password
		if(!$googleapi->login($params->{'username'}, $params->{'password'})) {
			$params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_LOGIN_FAILED');
		} else {
			$params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_LOGIN_SUCCESS');
			if ($params->{'device_id'}) {
				$prefs->set('device_id', $params->{'device_id'});
			} else {
				# If no mobile device ID provided try to set it automatically
				my $device_id = Plugins::GoogleMusic::GoogleAPI::get_device_id($params->{'username'},
																			   $params->{'password'});
				if ($device_id) {
					$prefs->set('device_id', $device_id);
				} else {
					$params->{'warning'} .= " " . cstring($client, 'PLUGIN_GOOGLEMUSIC_NO_DEVICE_ID');
				}
			}
		}
	}

	if ($params->{'saveSettings'}) {
		$prefs->set('all_access_enabled',  $params->{'all_access_enabled'} ? 1 : 0);
		for my $param(qw(max_search_items max_artist_tracks max_related_artists)) {
			if ($params->{ $param } ne $prefs->get( $param )) {
				$prefs->set($param, $params->{ $param });
			}
		}
	}

	# To avoid showing the password remove it from the list
	for my $param(qw(username password device_id all_access_enabled max_search_items max_artist_tracks max_related_artists)) {
		$params->{'prefs'}->{$param} = $prefs->get($param);
	}

	return $class->SUPER::handler($client, $params);
}

1;

__END__
