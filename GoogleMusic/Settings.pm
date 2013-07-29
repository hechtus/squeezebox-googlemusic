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

	if ($params->{'saveSettings'} && $params->{'username'} && $params->{'password'}) {
		$prefs->set('username', $params->{'username'});
		$prefs->set('password', $params->{'password'});
	}

	$params->{'prefs'}->{'username'} = $prefs->get('username');
	# To avoid showing the password remove this
	$params->{'prefs'}->{'password'} = $prefs->get('password');

	return $class->SUPER::handler($client, $params);
}

1;

__END__
