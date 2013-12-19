package Plugins::GoogleMusic::RadioProtocolHandler;

# Inspired by the Triode's Spotify Plugin

use strict;

Slim::Player::ProtocolHandlers->registerHandler(googlemusicradio => __PACKAGE__);

sub overridePlayback {
	my ( $class, $client, $url ) = @_;

	if ($url =~ /^googlemusicradio:station:(.*)$/) {

		$client->execute(["googlemusicradio", "station", $1]);

		return 1;
	}

	return undef;
}

sub canDirectStream { 0 }

sub isRemote { 0 }

sub contentType {
	return 'googlemusicradio';
}

sub getIcon {
	return Plugins::GoogleMusic::Plugin->_pluginDataFor('icon');
}


1;
