package Plugins::GoogleMusic::Radio;

# Inspired by the Triode's Spotify Plugin

use strict;
use warnings;

use List::Util qw(max);

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
	Slim::Control::Request::subscribe(\&commandCallback, [['playlist'], ['newsong', 'delete', 'index', 'jump', @stopcommands]]);

	return;
}

# Google Music All Access My Radio Stations menu
sub menu {
	my ($client, $callback, $args) = @_;

	my $stations;
	my @menu;

	# Get all user created stations
	$stations = Plugins::GoogleMusic::AllAccess::getStations();

	# Build the Menu
	for my $station (sort { $a->{name} cmp $b->{name} } @{$stations}) {
		my $image = '/html/images/radio.png';
		if (exists $station->{imageUrl}) {
			$image = $station->{imageUrl};
			$image = Plugins::GoogleMusic::Image->uri($image);
		}

		push @menu, {
			name => $station->{name},
			play => "googlemusicradio:station:$station->{id}",
			image => $image,
			items => stationInfo($client, $station),
			on_select => 'play',
			textkey => substr($station->{name}, 0, 1),
		};
	}

	# List of stations may be possibly empty
	if (!scalar @menu) {
		push @menu, {
			name => cstring($client, 'EMPTY'),
			type => 'text',
		}
	}

	return $callback->(\@menu);
}

sub stationInfo {
	my ($client, $station) = @_;

	return [{
		type => 'link',
		name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RADIO_STATION_DELETE'),
		url  => \&deleteStation,
		passthrough => [ $station->{id} ],
		nextWindow => 'parent',
		forceRefresh => 1,
		favorites => 0,
	}, {
		type  => 'text',
		label => 'URL',
		name  => "googlemusicradio:station:$station->{id}",
	}];
}

sub deleteStation {
	my ($client, $callback, $args, $id) = @_;

	my $msg;

	if (!Plugins::GoogleMusic::AllAccess::deleteStation($id)) {
		$log->error("Not able to delete radio station $id");
		$msg = cstring($client, 'PLUGIN_GOOGLEMUSIC_ERROR');
	} else {
		$msg = cstring($client, 'PLUGIN_GOOGLEMUSIC_RADIO_STATION_DELETED');
	}

	return $callback->({
		items => [{
			type => 'text',
			name => $msg,
			showBriefly => 1,
			popback => 2
		}]
	});
}

# Google Music All Access Radio Genres menu feed
sub genresFeed {
	my ($client, $callback, $args, $id) = @_;

	my $genres;
	my @menu;

	# If an ID is present we are getting child genres
	if ($id) {
		# Create a menu entry for the parent genre
		my $genre = Plugins::GoogleMusic::AllAccess::getGenre('googlemusic:genre:' . $id);
		push @menu, {
			name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RADIO_ALL') . " " . $genre->{name},
			type => 'audio',
			url => 'googlemusicradio:genre:' . $genre->{id},
			image => $genre->{image},
		};
		# Get the child genres for the parent ID
		$genres = Plugins::GoogleMusic::AllAccess::getGenres('googlemusic:genres:' . $id);
	} else {
		# Get all parent genres
		$genres = Plugins::GoogleMusic::AllAccess::getGenres('googlemusic:genres');
	}

	# Build the rest of the menu
	for my $genre (@{$genres}) {
		if ($id) {
			# If a parent ID was given we will add playable child nodes
			push @menu, {
				name => $genre->{name},
				type => 'audio',
				url => 'googlemusicradio:genre:' . $genre->{id},
				image => $genre->{image},
			};
		} else {
			# When parsing parent genres create a link to individual parent menus
			push @menu, {
				name => $genre->{name},
				type => 'link',
				url => \&genresFeed,
				image => $genre->{image},
				passthrough => [ $genre->{id} ],
			};
		}
	}

	# List of genres may be possibly empty due to an error
	if (!scalar @menu) {
		push @menu, {
			name => cstring($client, 'EMPTY'),
			type => 'text',
		}
	}

	$callback->(\@menu);

	return;

}

# Start Google Music Radio feed
#
# Does not support album and track IDs from My Library
sub startRadioFeed {
	my ($client, $callback, $args, $url) = @_;

	return unless $client;

	if ($url =~ /^googlemusic:station:(.*)$/) {

		$client->execute(["googlemusicradio", "station", $1]);

		return $callback->();
	} elsif ($url =~ /^googlemusic:artist:(.*)$/) {

		$client->execute(["googlemusicradio", "artist", $1]);

		return $callback->();
	} elsif ($url =~ /^googlemusic:album:(.*)$/) {

		$client->execute(["googlemusicradio", "album", $1]);

		return $callback->();
	} elsif ($url =~ /^googlemusic:track:(.*)$/) {

		$client->execute(["googlemusicradio", "track", $1]);

		return $callback->();
	} elsif ($url =~ /^googlemusic:genre:(.*)$/) {

		$client->execute(["googlemusicradio", "genre", $1]);

		return $callback->();
	}

	$log->error("Not able to start radio for URL $url");

	return $callback->({
		items => [{
			name => cstring($client, 'PLUGIN_GOOGLEMUSIC_ERROR'),
			showBriefly => 1,
		}]
	});
	
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
	} elsif ($type eq 'artist') {
		my $station;
		my $artistID = $request->getParam('_p2');
		my $artist = Plugins::GoogleMusic::AllAccess::get_artist_info("googlemusic:artist:$artistID");

		$log->info("Creating Google Music radio station for artist ID $artistID");

		eval {
			$station = $googleapi->create_station($artist->{name}, $Inline::Python::Boolean::False, $artistID, $Inline::Python::Boolean::False, $Inline::Python::Boolean::False);
		};
		if ($@) {
			$log->error("Not able to create artist radio station for artist ID $artistID: $@");
		} else {
			$log->info("Playing Google Music radio station: $station");
			_playRadio($client, { station => $station });
		}
	} elsif ($type eq 'album') {
		my $station;
		my $albumID = $request->getParam('_p2');
		my $album = Plugins::GoogleMusic::AllAccess::get_album_info("googlemusic:album:$albumID");

		$log->info("Creating Google Music radio station for album ID $albumID");

		eval {
			$station = $googleapi->create_station($album->{name}, $Inline::Python::Boolean::False, $Inline::Python::Boolean::False, $albumID, $Inline::Python::Boolean::False);
		};
		if ($@) {
			$log->error("Not able to create album radio station for album ID $albumID: $@");
		} else {
			$log->info("Playing Google Music radio station: $station");
			_playRadio($client, { station => $station });
		}
	} elsif ($type eq 'track') {
		my $station;
		my $trackID = $request->getParam('_p2');
		my $track = Plugins::GoogleMusic::Library::get_track("googlemusic:track:$trackID");

		$log->info("Creating Google Music radio station for track ID $trackID");

		eval {
			$station = $googleapi->create_station($track->{title}, $trackID, $Inline::Python::Boolean::False, $Inline::Python::Boolean::False, $Inline::Python::Boolean::False);
		};
		if ($@) {
			$log->error("Not able to create track radio station for track ID $trackID: $@");
		} else {
			$log->info("Playing Google Music radio station: $station");
			_playRadio($client, { station => $station });
		}
	} elsif ($type eq 'genre') {
		my $station;
		my $genreID = $request->getParam('_p2');
		my $genre = Plugins::GoogleMusic::AllAccess::getGenre("googlemusic:genre:$genreID");

		$log->info("Creating Google Music radio station for genre ID $genreID");

		eval {
			$station = $googleapi->create_station($genre->{name}, $Inline::Python::Boolean::False, $Inline::Python::Boolean::False, $Inline::Python::Boolean::False, $genreID);
		};
		if ($@) {
			$log->error("Not able to create genre radio station for genre ID $genreID: $@");
		} else {
			$log->info("Playing Google Music radio station: $station");
			_playRadio($client, { station => $station });
		}
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
		$master->pluginData('recentlyPlayed', []);
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
				year    => $entry->{'year'},
				secs    => $entry->{'secs'},
				cover   => $entry->{'cover'},
				tracknum=> $entry->{'trackNumber'},
			});

			if ($obj) {
				$obj->stash->{'rating'} = $entry->{'rating'};
				push @tracksToAdd, $obj;
			}

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

	my $recentlyPlayed = $master->pluginData('recentlyPlayed') || [];
	my $station = $args->{'station'};
	my $googleTracks;

	# Get new tracks for the station
	eval {
		if (Plugins::GoogleMusic::GoogleAPI::get_version() lt '4.1.0') {
			$googleTracks = $googleapi->get_station_tracks($station, $PLAYLIST_MAXLENGTH);
		} else {
			$googleTracks = $googleapi->get_station_tracks($station, $PLAYLIST_MAXLENGTH, $recentlyPlayed);
		}
	};
	if ($@) {
		$log->error("Not able to get tracks for station $station: $@");
		$googleTracks = [];
	}

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
		push @{$recentlyPlayed}, $track->{id};
	}

	# Limit the number of recently played tracks to 50 as Google does
	splice @$recentlyPlayed, 0, max(scalar @$recentlyPlayed - 50, 0);

	$master->pluginData('recentlyPlayed', $recentlyPlayed);

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
			$master->pluginData('recentlyPlayed', []);
			$master->pluginData('args', {});
			
			if ($master->can('inhibitShuffle') && $master->inhibitShuffle && $master->inhibitShuffle eq 'googlemusicradio') {
				$master->inhibitShuffle(undef);
			}
			
		} elsif ($request->isCommand([['playlist'], ['newsong', 'index', 'jump']] ||
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
