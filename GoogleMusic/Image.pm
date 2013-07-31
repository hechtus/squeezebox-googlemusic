package Plugins::GoogleMusic::Image;

use strict;

use Slim::Utils::Log;

my $log = logger('plugin.googlemusic');

# TBD: We could do this, but for now we use the squeezebox image proxy
sub handler {
	my ($httpClient, $response) = @_;

	my $path = $response->request->uri;

	$path =~ /\/googlemusicimage\:(.*?)\/image #
			(?:_(X|\d+)x(X|\d+))? # width and height are given here, e.g. 300x300
			(?:_([sSfFpcom]))?    # resizeMode, given by a single character
			(?:_([\da-fA-F]+))?   # background color, optional
			/ix;	
}

sub uri {
	# Sometimes there is an https: prefix. Remove it.
	$_[1] =~ s/^https\://;
	# Very often there is already a size spec from Google. Remove it also.
	$_[1] =~ s/\=(.*)$//;

    return "https:$_[1]";
	# TBD: Do this if we want to ask Google for resizing
	# return "googlemusicimage:$_[1]/image";
}

1;
