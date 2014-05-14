package Plugins::GoogleMusic::SmartMix;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::SmartMix::Services;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

sub getId {
	my ($class, $client) = @_;

	return unless $client;

	return unless Slim::Utils::PluginManager->isEnabled('Plugins::GoogleMusic::Plugin');

	return if preferences('plugin.smartmix')->get('disable_GoogleMusic');

	return ( $googleapi->is_authenticated() ) ? 'GoogleMusic' : undef;
} 

sub getUrl {
	my ($class, $id, $client) = @_;

	# we can't handle the id - return a search handler instead
	return sub {
		$class->resolveUrl(@_);
	} if $class->getId($client); 
}

sub resolveUrl {
	my ($class, $cb, $args) = @_;

	my $searchResult = Plugins::GoogleMusic::AllAccess::search($args->{artist} . ' ' . $args->{title});

	if (!$searchResult->{tracks}) {
		$cb->();
	}

	my $candidates = [];
	my $searchArtist = $args->{artist};

	for my $track ( @{$searchResult->{tracks}} ) {
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
