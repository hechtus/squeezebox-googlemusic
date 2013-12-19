package Plugins::GoogleMusic::RadioProtocolHandler;

# Inspired by the Triode's Spotify Plugin

use strict;
use warnings;

Slim::Player::ProtocolHandlers->registerHandler(googlemusicradio => __PACKAGE__);

sub overridePlayback {
	my ( $class, $client, $url ) = @_;

	if ($url =~ /^googlemusicradio:station:(.*)$/) {

		$client->execute(["googlemusicradio", "station", $1]);

		return 1;
	}

	return;
}

sub canDirectStream {
	return 0;
}

sub isRemote {
	return 0;
}
sub contentType {
	return 'googlemusicradio';
}

sub getIcon {
	return Plugins::GoogleMusic::Plugin->_pluginDataFor('icon');
}


1;
