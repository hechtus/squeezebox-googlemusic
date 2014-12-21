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
	} elsif ($url =~ /^googlemusicradio:artist:(.*)$/) {

		$client->execute(["googlemusicradio", "artist", $1]);

		return 1;
	} elsif ($url =~ /^googlemusicradio:album:(.*)$/) {

		$client->execute(["googlemusicradio", "album", $1]);

		return 1;
	} elsif ($url =~ /^googlemusicradio:track:(.*)$/) {

		$client->execute(["googlemusicradio", "track", $1]);

		return 1;
	} elsif ($url =~ /^googlemusicradio:genre:(.*)$/) {

		$client->execute(["googlemusicradio", "genre", $1]);

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
