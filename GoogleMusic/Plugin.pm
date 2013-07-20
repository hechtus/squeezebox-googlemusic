package Plugins::GoogleMusic::Plugin;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Plugins::GoogleMusic::Settings;
use Scalar::Util qw(blessed);
use Slim::Control::Request;
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(string);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.googlemusic',
	'defaultLevel' => 'INFO',
#	'defaultLevel' => 'DEBUG',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.googlemusic');

# Any global variables? Go ahead and declare and/or set them here
our @browseMenuChoices;

sub getDisplayName {
	return 'PLUGIN_GOOGLEMUSIC';
}

# I have my own debug routine so that I can add the *** stuff easily.
sub myDebug {
	my $msg = shift;
	my $lvl = shift;
	
	if ($lvl eq "")
	{
		$lvl = "debug";
	}

	$log->$lvl("*** GoogleMusic *** $msg");
}

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		tag    => 'googlemusic',
		feed   => \&toplevel,
		is_app => 1,
		menu   => 'radios',
		weight => 1,
	);

	if (main::WEBUI) {
		Plugins::GoogleMusic::Settings->new;
	}

	# TBD: Login to Google
}

sub shutdownPlugin {
	# TBD: Logout from Google
}

sub toplevel {
	my ($client, $callback, $args) = @_;

	my @menu = (
		{ name => string('PLUGIN_GOOGLEMUSIC_PLAYLISTS'), type => 'link', url => \&sublevel, passthrough => [ 'Playlists' ] },
		{ name => string('PLUGIN_GOOGLEMUSIC_RECENT_SEARCHES'), type => 'link', url => \&sublevel, passthrough => [ 'searches' ] },
		{ name => string('PLUGIN_GOOGLEMUSIC_SEARCH'), type => 'search', url => \&sublevel },
	);

	$callback->(\@menu);
}

sub sublevel {

}

# Another old friend from pre-SC7.
# This is called when the plugin is selected by the user.
# So, initPlugin is called when the server starts up and is loading the plugins.
# setMode is called when the user navigates to the plugin on the squeezebox and navigates in or out of it.
sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;
	
	myDebug("In setmode");
	
	# Handle requests to exit this mode/plugin by going back to where the user was before they came
	# here.  If you don't this, pressing LEFT will just put you straight back to where you already
	# are! (try commenting out the following if statement) 
	if ($method eq 'pop') {
		# Pop the current mode off the mode stack and restore the previous one
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	
}
	
# Everything is handled by the input modes stuff
# So, just return and empty hash - NOTE THE CURLY BRACES with the return call! 
# I spent a while debugging a "bogus function" error because I had return() and not return{}.
# Normally this would return a reference to a functions hash that hashes button presses with actions.
sub getFunctions {

	return{};
}

1;

__END__
