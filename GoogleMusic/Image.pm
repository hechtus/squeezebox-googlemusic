package Plugins::GoogleMusic::Image;

# Inspired by the Triode's Spotify Plugin

use strict;
use warnings;

use List::Util qw[min];
use HTTP::Status qw(RC_OK RC_NOT_FOUND RC_SERVICE_UNAVAILABLE);

use Slim::Utils::Log;

use Readonly;
Readonly my $EXP_TIME => 60 * 60 * 24 * 7; # expire in one week
Readonly my $MAX_IMAGE_REQUEST => 5;       # max images to fetch from Google at once
Readonly my $IMAGE_REQUEST_TIMEOUT1 => 30; # max time to queue
Readonly my $IMAGE_REQUEST_TIMEOUT2 => 35; # max time to wait for response

my $log = logger('plugin.googlemusic');

my @fetchQ;   # Q of images to fetch
my %fetching; # hash of images being fetched

my $id = 0;

# Initialization of the module
sub init {
	Slim::Web::Pages->addRawFunction('/googlemusicimage', \&handler);

	return;
}

# TBD: We could do this, but for now we use the squeezebox image proxy
sub handler {
	my ($httpClient, $response) = @_;

	my $path = $response->request->uri;

	$path =~ /\/googlemusicimage\/(.*?)\/image #
			(?:_(X|\d+)x(X|\d+))? # width and height are given here, e.g. 300x300
			(?:_([sSfFpcom]))?    # resizeMode, given by a single character
			(?:_([\da-fA-F]+))?   # background color, optional
			\.jpg$
			/ix;

	my $image = $1;
	my $needsResize = defined $2 || defined $3 || defined $4 || defined $5 || 0;
	my $resizeParams = $needsResize ? [ $2, $3, $4, $5 ] : undef;

	if (!$image) {

		$log->info("bad image request - sending 404, path: $path");

		$response->code(RC_NOT_FOUND);
		$response->content_length(0);

		Slim::Web::HTTP::addHTTPResponse($httpClient, $response, '', 1, 0);

		return;
	}

	$id = ($id + 1) % 10_000;

	$log->info("queuing image id: $id request: $image (resizing: $needsResize)");

	push @fetchQ, { id => $id, timeout => time() + $IMAGE_REQUEST_TIMEOUT1, path => $path, 
					httpClient => $httpClient, response => $response, resizeP => $resizeParams, image => $image,
				  };

	$log->debug(sub { "fetchQ: " . (scalar @fetchQ) . " fetching: " . (scalar keys %fetching) });

	if (scalar keys %fetching < $MAX_IMAGE_REQUEST) {

		_fetch();

	} else {

		# handle case where we don't appear to get a callback for an async request and it has timed out
		for my $key (keys %fetching) {

			if ($fetching{$key}->{'timeout'} < time()) {

				$log->debug("stale fetch entry - closing");

				my $entry = delete $fetching{$key};

				_sendUnavailable($entry->{'httpClient'}, $entry->{'response'});

				_fetch();
			}
		}
	}

	return;
}


sub _fetch {
	my $entry;

	while (!$entry && @fetchQ) {

		 $entry = shift @fetchQ;

		 if (!$entry->{'httpClient'}->connected) {
			 $entry = undef;
			 next;
		 }

		 if ($entry->{'timeout'} < time()) {
			 _sendUnavailable($entry->{'httpClient'}, $entry->{'response'});
			 $entry = undef;
		 } 
	}

	return unless $entry;

	my $image = $entry->{'image'};
	my $resizeP = $entry->{'resizeP'};

	if ($resizeP) {
		my $s = min($resizeP->[0], $resizeP->[1]);
		$image .= "=s$s-c";
	}

	$log->info("fetching image: $image");

	$entry->{'timeout'} = time() + $IMAGE_REQUEST_TIMEOUT2;

	$fetching{ $entry->{'id'} } = $entry;

	Slim::Networking::SimpleAsyncHTTP->new(
		\&_gotImage, \&_gotError, $entry
		)->get("https://$image");

	return;
}

sub _gotImage {
	my $http = shift;
	my $httpClient = $http->params('httpClient');
	my $response   = $http->params('response');
	my $resizeP    = $http->params('resizeP');
	my $path       = $http->params('path');
	my $id         = $http->params('id');

	my $body;

	if ($httpClient->connected) {

		$response->code(RC_OK);
		$response->content_type('image/jpeg');
		
		$response->header('Cache-Control' => 'max-age=' . $EXP_TIME);
		$response->expires(time() + $EXP_TIME);
		
		use bytes;
		$response->content_length($body ? length($$body) : length($http->content));

		Slim::Web::HTTP::addHTTPResponse($httpClient, $response, $body || $http->contentRef, 1, 0);
	}

	delete $fetching{ $id };

	_fetch();

	return;
}

sub _gotError {
	my $http = shift;
	my $error = shift;
	my $httpClient = $http->params('httpClient');
	my $response   = $http->params('response');
	my $id         = $http->params('id');

	$log->warn("error: $error");

	_sendUnavailable($httpClient, $response);

	delete $fetching{ $id };

	_fetch();

	return;
}

sub _sendUnavailable {
	my $httpClient = shift;
	my $response   = shift;

	if ($httpClient->connected) {

		$response->code(RC_SERVICE_UNAVAILABLE);
		$response->header('Retry-After' => 10);
		$response->content_length(0);
		
		Slim::Web::HTTP::addHTTPResponse($httpClient, $response, '', 1, 0);
	}

	return;
}

sub uri {
	my ($client, $image) = @_;

	# Check if it's an squeezebox provided image
	if ($image =~ /^\/html\/images\//) {
		return $image;
	}

	# Sometimes there is an https:// prefix. Remove it.
	$image =~ s/^https?\:\/\///;
	# Very often there is already a size spec from Google. Remove it also.
	$image =~ s/\=(.*)$//;

	return "googlemusicimage/$image/image.jpg";
}


1;
