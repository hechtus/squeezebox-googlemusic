package Plugins::GoogleMusic::SmartMixAllAccess;

use strict;
use warnings;

use vars qw($VERSION);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::SmartMix::Services;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

sub init {
	($VERSION) = @_;

	return;
}

sub getId {
	my ($class, $client) = @_;

	return unless $client;

	return unless Slim::Utils::PluginManager->isEnabled('Plugins::GoogleMusic::Plugin');

	return if preferences('plugin.smartmix')->get('disable_GoogleMusicAllAccess');

	return ( $googleapi->is_authenticated() ) ? 'GoogleMusicAllAccess' : undef;
} 

sub getUrl {
	my ($class, $id, $client) = @_;

	# we can't handle the id - return a search handler instead
	return sub {
		$class->resolveUrl(@_);
	} if $class->getId($client);

	return;
}

sub resolveUrl {
	my ($class, $cb, $args) = @_;

	# Try to find the track through All Access. If it's not enabled we
	# will get an empty list here. Do not get more than five tracks to
	# keep performance.
	my $searchResult =
		Plugins::GoogleMusic::AllAccess::searchTracks(
			$args->{artist} . ' ' . $args->{title}, 5);

	# No success?
	if (!@$searchResult) {
		$cb->();
		return;
	}

	# Translate tracks to SmartMix canditates
	my $candidates = [];

	for my $track ( @$searchResult ) {
		# Double check fields, even if they should be all available.
		next unless $track->{artist} && $track->{uri} && $track->{title};
		push @$candidates, {
			title  => $track->{title},
			artist => $track->{artist}->{name},
			url    => $track->{uri},
		};
	}

	$cb->( Plugins::SmartMix::Services->getUrlFromCandidates($candidates, $args) );

	return;
}

sub urlToId {}

1;
