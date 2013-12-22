package Plugins::GoogleMusic::Radio;

# Inspired by the Triode's Spotify Plugin

use strict;
use warnings;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(cstring);

use Plugins::GoogleMusic::GoogleAPI;
use Plugins::GoogleMusic::Image;
use Plugins::GoogleMusic::RadioProtocolHandler;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

my $PLAYLIST_MAXLENGTH = 10;

my @stopcommands = qw(clear loadtracks playtracks load play loadalbum playalbum);


# Initialization of the module
sub init {
	Slim::Control::Request::addDispatch(['googlemusicradio', '_type'], [1, 0, 0, \&cliRequest]);
	Slim::Control::Request::subscribe(\&commandCallback, [['playlist'], ['newsong', 'delete', @stopcommands]]);

	return;
}

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
		$log->error("Not able to get user created radio stations");
		$stations = [];
	};

	# Build the Menu
	for my $station (@{$stations}) {
		push @menu, {
			name => $station->{name},
			type => 'audio',
			url => "googlemusicradio:station:$station->{id}",
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

sub cliRequest {
	my $request = shift;
 
	my $client = $request->client;
	my $type = $request->getParam('_type'); 

	if (Slim::Player::Playlist::shuffle($client)) {

		if ($client->can('inhibitShuffle')) {
			$client->inhibitShuffle('googlemusicradio');
		} else {
			$log->warn("WARNING: turning off shuffle mode");
			Slim::Player::Playlist::shuffle($client, 0);
		}
	}

	if ($type eq 'station') {
		my $station = $request->getParam('_p2');

		$log->info("Playing Google Music radio station: $station");
		_playRadio($client, { station => $station });
	}

	$request->setStatusDone();

	return;
}

sub _playRadio {
	my $master = shift->master;
	my $args   = shift;
	my $callback = shift;

	if ($args) {
		$master->pluginData('running', 1);
		$master->pluginData('args', $args);
		$master->pluginData('tracks', []);
	} else {
		$args = $master->pluginData('args');
	}

	return unless $master->pluginData('running');

	my $tracks = $master->pluginData('tracks');
	
	my $load = ($master->pluginData('running') == 1);

	my $tracksToAdd = $load ? $PLAYLIST_MAXLENGTH : $PLAYLIST_MAXLENGTH - scalar @{Slim::Player::Playlist::playList($master)};

	# for similar artists only add one track per artist per call until all artists lists have been fetched
	if ($tracksToAdd && ($args->{'similar'}) && !$args->{'allfetched'}) {
		$tracksToAdd = 1;
	}

	if ($tracksToAdd) {

		my @tracksToAdd;

		while ($tracksToAdd && scalar @$tracks) {

			my ($index, $entry);

			if ($args->{'rand'}) {

				# pick a random track, attempting to avoid one with the same title as last track
				# if called from a callback then pick from within the topmost $callback tracks ie from the most recent fetch
				# ensure the range of indexes considered shrinks as $tracks shrink so we always pick a track from the list
				my $consider = $callback || scalar @$tracks;
				if ($consider > scalar @$tracks) {
					$consider = scalar @$tracks;
				}

				my $tries = 3;
				do {

					$index = -int(rand($consider));

				} while ($tracks->[$index]->{'name'} ne ($master->pluginData('lasttitle') || '') && $tries--);

				$master->pluginData('lasttitle', $tracks->[$index]->{'name'});

			} else {

				# take first track
				$index = 0;
			}

			$entry = splice @$tracks, $index, 1;

			# create remote track obj late to ensure it stays in the S:S:RemoteTrack LRU
			my $obj = Slim::Schema::RemoteTrack->updateOrCreate($entry->{'uri'}, {
				title   => $entry->{'title'},
				artist  => $entry->{'artist'}->{'name'},
				album   => $entry->{'album'}->{'name'},
				secs    => $entry->{'secs'},
				cover   => $entry->{'cover'},
				tracknum=> $entry->{'trackNumber'},
			});

			push @tracksToAdd, $obj;

			$tracksToAdd--;
		}

		if (@tracksToAdd) {

			$log->info(($load ? "loading " : "adding ") . scalar @tracksToAdd . " tracks, pending tracks: " . scalar @$tracks);
			
			$master->execute(['playlist', $load ? 'loadtracks' : 'addtracks', 'listRef', \@tracksToAdd])->source('googlemusicradio');

			if ($load) {
				$master->pluginData('running', 2);
			}
		}
	}

	if ($tracksToAdd > 0 && !$callback) {

		if ($args->{'station'}) {

			$log->info("Fetching Google Music radio station tracks");

			fetchStationTracks($master, $tracks, $args);

		}
	}

	return;
}

sub fetchStationTracks {
	my ($master, $tracks, $args) = @_;

	my $station = $args->{'station'};
	my $googleTracks;

	# Get new tracks for the station
	eval {
		$googleTracks = $googleapi->get_station_tracks($station, $PLAYLIST_MAXLENGTH);
		1;
	} or do {
		$log->error("Not able to get tracks for station $station");
		$googleTracks = [];
	};

	# Convert to slim format and add to the list of tracks
	for my $googleTrack (@{$googleTracks}) {
		my $track;
		# Check if the track is in My Library
		if (exists $googleTrack->{id}) {
			$track = Plugins::GoogleMusic::Library::get_track_by_id($googleTrack->{id});
		} else {
			$track = Plugins::GoogleMusic::AllAccess::to_slim_track($googleTrack);
		}
		push @{$tracks}, $track;
	}

	my $newtracks = scalar @{$googleTracks || []};

	$log->info(sub{ sprintf("got %d tracks, pending tracks now %s", $newtracks, scalar @$tracks) });

	_playRadio($master, undef, $newtracks) if $newtracks;

	return;
}

sub commandCallback {
	my $request = shift;
	my $client  = $request->client;
	my $master  = $client->master;

	$log->is_debug && $log->debug(sprintf("[%s] %s source: %s", $request->getRequestString, 
		Slim::Player::Sync::isMaster($client) ? 'master' : 'slave',	$request->source || ''));

	return if $request->source && $request->source eq 'googlemusicradio';

	return if $request->isCommand([['playlist'], ['play', 'load']]) && $request->getParam('_item') =~ "^googlemusicradio:";

	if ($master->pluginData('running')) {

		my $songIndex = Slim::Player::Source::streamingSongIndex($master);
		
		if ($request->isCommand([['playlist'], [@stopcommands]])) {
			
			$log->info("stopping radio");
			
			$master->pluginData('running', 0);
			$master->pluginData('tracks', []);
			$master->pluginData('args', {});
			
			if ($master->can('inhibitShuffle') && $master->inhibitShuffle && $master->inhibitShuffle eq 'googlemusicradio') {
				$master->inhibitShuffle(undef);
			}
			
		} elsif ($request->isCommand([['playlist'], ['newsong']] ||
				 ($request->isCommand([['playlist'], ['delete']]) && $request->getParam('_index') > $songIndex)
				)) {
				
			$log->info("playlist changed - checking whether to add or remove tracks");
			
			if ($songIndex && $songIndex >= int($PLAYLIST_MAXLENGTH / 2)) {
				
				my $remove = $songIndex - int($PLAYLIST_MAXLENGTH / 2) + 1;
				
				$log->info("removing $remove track(s) songIndex: $songIndex");
				
				while ($remove--) {
					$master->execute(['playlist', 'delete', 0])->source('googlemusicradio');
				}
			}
			
			_playRadio($master);
		}
	}

	return;
}


1;
