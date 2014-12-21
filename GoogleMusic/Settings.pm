package Plugins::GoogleMusic::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;
use base qw(Slim::Web::Settings);

use MIME::Base64;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Prefs;
use Slim::Utils::OSDetect;

use Plugins::GoogleMusic::GoogleAPI;

my $os = Slim::Utils::OSDetect->getOS();
my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

$prefs->init({
	username => '',
	password => '',
	disable_ssl => 0,
	my_music_album_sort_method => 'artistyearalbum',
	all_access_album_sort_method => 'none',
	max_search_items => 100,
	max_artist_tracks => 25,
	max_related_artists => 10,
});

$prefs->migrate(1, sub { 
	$prefs->set('password', encode_base64($prefs->get('password'), ''));
	return 1;
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

	if ($params->{'saveSettings'} && $params->{'username'} && $params->{'password'} &&
	    (($params->{'username'} ne $prefs->get('username')) || 
	     (encode_base64($params->{'password'}, '') ne $prefs->get('password')))) {
		$prefs->set('username', $params->{'username'});
		$prefs->set('password', encode_base64($params->{'password'}, ''));

		# Logout from Google
		$googleapi->logout();

		# Now try to login with new username/password. If SSL
		# verification fails, login() raises an exception. Catch it to
		# be able to show the settings page correctly, so that the
		# user is able to disable SSL verification.
		eval {
			$googleapi->login($prefs->get('username'),
							  decode_base64($prefs->get('password')));
		};
		if ($@) {
			$log->error("Not able to login to Google Play Music: $@");
		}

		if(!$googleapi->is_authenticated()) {
			$params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_LOGIN_FAILED');
		} else {
			$params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_LOGIN_SUCCESS');
			# Load My Music and Playlists
			Plugins::GoogleMusic::Library::refresh();
			Plugins::GoogleMusic::Playlists::refresh();
		}
	}

	if ($params->{'saveSettings'}) {
		if ($params->{'device_id'}) {
			$prefs->set('device_id', $params->{'device_id'});
		} else {
			# If no mobile device ID provided try to set it automatically
			my $device_id;
			if($googleapi->is_authenticated()) {
				$device_id = Plugins::GoogleMusic::GoogleAPI::get_device_id($params->{'username'},
																			$params->{'password'});
			}
			if ($device_id) {
				$prefs->set('device_id', $device_id);
			} else {
				$params->{'warning'} .= " " . cstring($client, 'PLUGIN_GOOGLEMUSIC_NO_DEVICE_ID');
			}
		}
	}

	if ($params->{'saveSettings'}) {
		$prefs->set('all_access_enabled',  $params->{'all_access_enabled'} ? 1 : 0);
		for my $param(qw(my_music_album_sort_method all_access_album_sort_method max_search_items max_artist_tracks max_related_artists)) {
			if ($params->{ $param } ne $prefs->get( $param )) {
				$prefs->set($param, $params->{ $param });
			}
		}
	}

	if ($params->{'saveSettings'}) {
		my $disable_ssl = $params->{'disable_ssl'} ? 1 : 0;
		if ($disable_ssl != $prefs->get('disable_ssl')) {
			$prefs->set('disable_ssl',  $disable_ssl);
			$params = $class->getRestartMessage($params, cstring($client, 'SETUP_GROUP_PLUGINS_NEEDS_RESTART'));
		}
	}		

	for my $param(qw(username device_id disable_ssl my_music_album_sort_method all_access_enabled all_access_album_sort_method max_search_items max_artist_tracks max_related_artists)) {
		$params->{'prefs'}->{$param} = $prefs->get($param);
	}

	# The password is obfuscated by the settings page
	$params->{'prefs'}->{'password'} = decode_base64($prefs->get('password'));

	$params->{'album_sort_methods'} = {
		'none'            => cstring($client, 'NONE'),
		'album'           => cstring($client, 'ALBUM'),
		'artistalbum'     => cstring($client, 'SORT_ARTISTALBUM'),
		'artistyearalbum' => cstring($client, 'SORT_ARTISTYEARALBUM'),
		'yearalbum'       => cstring($client, 'SORT_YEARALBUM'),
		'yearartistalbum' => cstring($client, 'SORT_YEARARTISTALBUM'),
	};

	$params = $class->restartServer($params, 1);

	return $class->SUPER::handler($client, $params);
}

sub getRestartMessage {
	my ($class, $paramRef, $noRestartMsg) = @_;
	
	# show a link/button to restart SC if this is supported by this platform
	if ($os->canRestartServer()) {
				
		$paramRef->{'restartUrl'} = $paramRef->{webroot} . $paramRef->{path} . '?restart=1';
		$paramRef->{'restartUrl'} .= '&rand=' . $paramRef->{'rand'} if $paramRef->{'rand'};

		$paramRef->{'warning'} = '<span id="restartWarning">'
			. Slim::Utils::Strings::string('PLUGINS_CHANGED_NEED_RESTART', $paramRef->{'restartUrl'})
			. '</span>';

	} else {
	
		$paramRef->{'warning'} .= '<span id="popupWarning">'
			. $noRestartMsg
			. '</span>';
		
	}
	
	return $paramRef;	
}

sub restartServer {
	my ($class, $paramRef, $needsRestart) = @_;
	
	if ($needsRestart && $paramRef->{restart} && $os->canRestartServer()) {
		
		$paramRef->{'warning'} = '<span id="popupWarning">'
			. Slim::Utils::Strings::string('RESTARTING_PLEASE_WAIT')
			. '</span>';
		
		# delay the restart a few seconds to return the page to the client first
		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 2, \&_restartServer);
	}
	
	return $paramRef;
}

sub _restartServer {

	return $os->restartServer();

}

1;

__END__
