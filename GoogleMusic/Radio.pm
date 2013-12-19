package Plugins::GoogleMusic::Radio;

use strict;
use warnings;

use Data::Dumper;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(cstring string);

use Plugins::GoogleMusic::GoogleAPI;
use Plugins::GoogleMusic::Image;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

# Google Music All Access Radio menu
sub menu {
	my ($client, $callback, $args) = @_;

	my $stations;
	my @menu;

	# Get all user created stations
	eval {
		$stations = $googleapi->get_all_stations();
		1;
	} or do {
		$stations = [];
	};

	# Build the Menu
	for my $station (@{$stations}) {
		push @menu, {
			name => $station->{name},
			type => 'audio',
			url => "googlemusicradio:$station->{id}",
			image => Plugins::GoogleMusic::Image->uri($station->{imageUrl}),
		};
	}

	# List of stations may be possibly empty
	if (!scalar @menu) {
		push @menu, {
			name => cstring($client, 'EMPTY'),
			type => 'text',
		}
	}

	$callback->(\@menu);

	return;

}

1;
