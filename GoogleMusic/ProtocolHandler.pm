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
	  
	my ($id) = $url =~ m{^googlemusic:track:(.*)$};

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

sub getMetadataFor {
	# don't use $_[3] as it is forceCurrent used by AudioScrobbler
	my ($class, $client, $url, undef, $fetch) = @_; 

	my $track = $googleapi->get_track($url);
	my $secs = $track->{'durationMillis'} / 1000;

	return {
		title    => $track->{'name'},
		artist   => $track->{'artist'},
		album    => $track->{'album'},
		secs     => $secs,
		duration => sprintf('%d:%02d', int($secs / 60), $secs % 60),
		cover    => $track->{'albumArtUrl'},
		# Icon does not work as Squeezebox appends some size request to the URL
		# We will need an image resizer ... :-(
		# icon    => $track->{'albumArtUrl'},
		bitrate  => '320k',
		type     => 'MP3 (Google Music)',
		albumuri => $track->{'myAlbum'}->{'uri'},
		artistA  => $track->{'myAlbum'}->{'artist'},
	};
}
