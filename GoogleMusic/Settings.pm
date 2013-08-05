package Plugins::GoogleMusic::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

use Plugins::GoogleMusic::GoogleAPI;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_GOOGLEMUSIC');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/GoogleMusic/settings/basic.html');
}

sub handler {
	my ($class, $client, $params) = @_;

	if (!$googleapi->is_authenticated()) {
		$params->{'warning'} = string('PLUGIN_GOOGLEMUSIC_NOT_LOGGED_IN');
	}

	if ($params->{'saveSettings'} && $params->{'username'} && $params->{'password'} && $params->{'device_id'}) {
		$prefs->set('username', $params->{'username'});
		$prefs->set('password', $params->{'password'});
		$prefs->set('device_id', $params->{'device_id'});

		# Logout from Google
		$googleapi->logout();
		# Now try to login with new username/password
		if(!$googleapi->login($params->{'username'}, $params->{'password'})) {
			$params->{'warning'} = string('PLUGIN_GOOGLEMUSIC_LOGIN_FAILED');
		} else {
			$params->{'warning'} = string('PLUGIN_GOOGLEMUSIC_LOGIN_SUCCESS');
		}
	}

	$params->{'prefs'}->{'username'} = $prefs->get('username');
	# To avoid showing the password remove this
	$params->{'prefs'}->{'password'} = $prefs->get('password');
	$params->{'prefs'}->{'device_id'} = $prefs->get('device_id');

	return $class->SUPER::handler($client, $params);
}

1;

__END__
