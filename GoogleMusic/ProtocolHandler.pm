package Plugins::GoogleMusic::ProtocolHandler;

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use Scalar::Util qw(blessed);
use URI::Escape qw(uri_escape_utf8);

use Slim::Player::Playlist;
use Slim::Utils::Log;
use Slim::Utils::Misc;

use Plugins::GoogleMusic::Plugin;
use Plugins::GoogleMusic::GoogleAPI;

my $log = logger('plugin.googlemusic');

Slim::Player::ProtocolHandlers->registerHandler('googlemusic', __PACKAGE__);

# Always MP3
sub getFormatForURL { 'mp3' }

# Avoid scanning
sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{cb}->( $args->{song}->currentTrack() );
}

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	  
	my $url    = $song->currentTrack()->url;
	  
	my ($id) = $url =~ m{^googlemusic:(.*)$};

	my $trackURL = $googleapi->get_stream_url($id);

	$song->streamUrl($trackURL);

	$successCb->();
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $song->streamUrl(), $class->getFormatForURL() );
}
