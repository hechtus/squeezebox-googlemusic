package Plugins::GoogleMusic::AllAccess;

use strict;
use warnings;
use Readonly;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;

use Plugins::GoogleMusic::GoogleAPI;

# Cache most of the results for one hour
Readonly my $CACHE_TIME => 3600;
# Cache track information for one day because get_album_info() would
# be used too often
Readonly my $CACHE_TIME_LONG => 24 * 3600;
# Cache user modifiable data shorlty
Readonly my $CACHE_TIME_SHORT => 30;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();
my $cache;

sub init {
	$cache = shift;

	return;
}

# Convert an All Access Google Music Song dictionary to a consistent
# robust track representation
sub to_slim_track {
	my $song = shift;

	my $uri = 'googlemusic:track:' . $song->{storeId};

	if (my $track = $cache->get($uri)) {
		return $track;
	}

	my $cover = '/html/images/cover.png';
	if (exists $song->{albumArtRef}) {
		$cover = $song->{albumArtRef}[0]{url};
		$cover = Plugins::GoogleMusic::Image->uri($cover);
	}

	# Get/create the album for this song
	my $album = to_slim_album($song);

	# Build track info
	my $track = {
		uri => $uri,
		id => $song->{storeId},
		title => $song->{title},
		album => $album,
		artist => to_slim_artist($song),
		year => $song->{year} || 0,
		cover => $cover,
		secs => $song->{durationMillis} / 1000,
		bitrate => 320,
		genre => $song->{genre},
		filesize => $song->{estimatedSize},
		trackNumber => $song->{trackNumber} || 1,
		discNumber => $song->{discNumber} || 1,
		rating => $song->{rating} || 0,
	};

	# Add to the cache
	$cache->set($uri, $track, $CACHE_TIME_LONG);

	return $track;
}

# Convert an All Access Google Music Song dictionary to a consistent
# robust album representation
sub to_slim_album {
	my $song = shift;

	my $artist = to_slim_album_artist($song);
	my $name = $song->{album};
	my $year = $song->{year} || 0;

	my $uri = 'googlemusic:album:' . $song->{albumId};

	my $cover = '/html/images/cover.png';
	if (exists $song->{albumArtRef}) {
		$cover = $song->{albumArtRef}[0]{url};
		$cover = Plugins::GoogleMusic::Image->uri($cover);
	}

	my $album = {
		uri => $uri,
		id => $song->{albumId},
		name => $name,
		artist => $artist,
		year => $year,
		cover => $cover,
		tracks => [],
	};

	return $album;
}

# Convert an All Access Google Music Song dictionary to a consistent
# robust artist representation
sub to_slim_artist {
	my $song = shift;

	my $id = scalar $song->{artistId} ? $song->{artistId}[0] : 'unknown';
	my $uri = 'googlemusic:artist:' . $id;
	my $name = $song->{artist};

	my $image = '/html/images/artists.png';
	if (exists $song->{artistArtRef}) {
		$image = $song->{artistArtRef}[0]{url};
		$image = Plugins::GoogleMusic::Image->uri($image);
	}

	my $artist = {
		uri => $uri,
		id => $id,
		name => $name,
		image => $image,
	};

	return $artist;
}

# Convert an All Access Google Music Song dictionary to a consistent
# robust album artist representation
sub to_slim_album_artist {
	my $song = shift;

	# In one test case (the band 'Poliça') GoogleMusic messed up the
	# 'artist' is sometime lowercase, where the 'albumArtist' is
	# uppercase the albumArtist is the most consistent so take that or
	# else we will see multiple entries in the Artists listing (lower
	# + upper case)
	my $name = $song->{albumArtist} || $song->{artist};
	
	# TODO: No album artist ID in tracks. Should we fetch the album info?
	my $uri = 'googlemusic:artist:unknown';

	my $image = '/html/images/artists.png';
	# Check to see if this album is a compilation from various
	# artists. The Google Music webinterface also shows a 'Various
	# artists' in my library instead of all seperate artists.. which
	# should justify this functionality
	my $various = (index(lc($song->{artist}), lc($song->{albumArtist} || '')) == -1) ? 1 : 0;
	if (exists $song->{artistArtRef} and not $various) {
		$image = $song->{artistArtRef}[0]{url};
		$image = Plugins::GoogleMusic::Image->uri($image);
	}
	
	my $artist = {
		uri => $uri,
		id => 'unknown',
		name => $name,
		various => $various,
		image => $image,
	};

	return $artist;
}

sub get_track {
	my $uri = shift;

	return unless $prefs->get('all_access_enabled');

	if (my $track = $cache->get($uri)) {
		return $track;
	}

	my ($id) = $uri =~ m{^googlemusic:track:(.*)$}x;
	my $song;

	eval {
		# For some reasons Google only knows this does not return the
		# rating of the track. Surprisingly, fetching the whole album
		# returns the rating. Thus, we get the track info and after
		# that the album info for that track.
		$song = $googleapi->get_track_info($id);
	};
	if ($@) {
		$log->error("Not able to get the track info for track ID $id: $@");
		return;
	}

	# Get the album and process all tracks to get them into the cache
	my $album = get_album_info('googlemusic:album:' . $song->{albumId});

	# Get the track from the cache including the rating field :-)
	if (my $track = $cache->get($uri)) {
		return $track;
	}

	$log->error("Not able to get the track info for track ID $id from the album information");

	return;
}

sub get_track_by_id {
	my $id = shift;

	return get_track('googlemusic:track:' . $id);
}

# Search All Access
sub search {
	my $query = shift;

	return unless $prefs->get('all_access_enabled');

	my $uri = 'googlemusic:search:' . $query;

	if (my $result = $cache->get($uri)) {
		return $result;
	}

	my $googleResult;
	my $result = {
		tracks => [],
		albums => [],
		artists => [],
	};		  

	eval {
		$googleResult = $googleapi->search_all_access($query, $prefs->get('max_search_items'));
	};
	if ($@) {
		$log->error("Not able to search All Access for \"$query\": $@");
		return;
	}
	for my $hit (@{$googleResult->{song_hits}}) {
		push @{$result->{tracks}}, to_slim_track($hit->{track});
	}
	for my $hit (@{$googleResult->{album_hits}}) {
		push @{$result->{albums}}, album_to_slim_album($hit->{album});
	}
	for my $hit (@{$googleResult->{artist_hits}}) {
		push @{$result->{artists}}, artist_to_slim_artist($hit->{artist});
	}

	# Add to the cache
	$cache->set($uri, $result, $CACHE_TIME);

	return $result;
}

# Search All Access tracks only. Do not cache these searches for now.
sub searchTracks {
	my ($query, $maxResults) = @_;

	my $googleResult;
	my $tracks = [];

	return $tracks unless $prefs->get('all_access_enabled');

	eval {
		$googleResult = $googleapi->search_all_access($query, $maxResults);
	};

	if ($@) {
		$log->error("Not able to search All Access for \"$query\": $@");
	} else {
		for my $hit (@{$googleResult->{song_hits}}) {
			push @$tracks, to_slim_track($hit->{track});
		}
	}

	return $tracks;
}

# Get information for an artist
sub get_artist_info {
	my $uri = shift;

	return unless $prefs->get('all_access_enabled');

	if (my $artist = $cache->get($uri)) {
		return $artist;
	}

	my ($id) = $uri =~ m{^googlemusic:artist:(.*)$}x;

	my $googleArtist;
	my $artist;

	eval {
		$googleArtist = $googleapi->get_artist_info($id, $Inline::Python::Boolean::true, $prefs->get('max_artist_tracks'), $prefs->get('max_related_artists'));
	};
	if ($@) {
		$log->error("Not able to get the artist info for artist ID $id: $@");
		return;
	}
	
	$artist = artist_to_slim_artist($googleArtist);

	# Add to the cache
	$cache->set($uri, $artist, $CACHE_TIME);

	return $artist;
}

sub get_artist_image {
	my $uri = shift;

	return unless $prefs->get('all_access_enabled');

	# First try to get the image from the artist cache
	if (my $artist = $cache->get($uri)) {
		return $artist->{image};
	}

	my ($id) = $uri =~ m{^googlemusic:artist:(.*)$}x;

	my $imageuri = 'googlemusic:artistimage:' . $id;

	if (my $artistImage = $cache->get($imageuri)) {
		return $artistImage;
	}

	my $googleArtist;

	eval {
		$googleArtist = $googleapi->get_artist_info($id, $Inline::Python::Boolean::false, 0, 0);
	};
	if ($@) {
		$log->error("Not able to get the artist image for artist ID $id: $@");
	}

	my $image = '/html/images/artists.png';
	if ($googleArtist && exists $googleArtist->{artistArtRef}) {
		$image = $googleArtist->{artistArtRef};
		$image = Plugins::GoogleMusic::Image->uri($image);
	}

	# Add to the cache
	$cache->set($imageuri, $image, $CACHE_TIME);

	return $image;
}

# Get information for an album
sub get_album_info {
	my $uri = shift;

	return unless $prefs->get('all_access_enabled');

	if (my $album = $cache->get($uri)) {
		return $album;
	}

	my ($id) = $uri =~ m{^googlemusic:album:(.*)$}x;

	my $googleAlbum;
	my $album;

	eval {
		$googleAlbum = $googleapi->get_album_info($id);
	};
	if ($@) {
		$log->error("Not able to get the album info for album ID $id: $@");
		return;
	}

	$album = album_to_slim_album($googleAlbum);

	# Add to the cache
	$cache->set($uri, $album, $CACHE_TIME);

	return $album;
}

# Convert an All Access Google album dictionary to a consistent
# robust album representation
sub album_to_slim_album {
	my $googleAlbum = shift;

	my $artistId = scalar $googleAlbum->{artistId} ? $googleAlbum->{artistId}[0] : 'unknown';

	# TODO: Sometimes the array has multiple entries
	my $artist = {
		uri => 'googlemusic:artist:' . $artistId,
		id => $artistId,
		name => $googleAlbum->{albumArtist} || $googleAlbum->{artist},
		various => 0,
	};

	my $name = $googleAlbum->{name};
	my $year = $googleAlbum->{year} || 0;

	my $uri = 'googlemusic:album:' . $googleAlbum->{albumId};

	my $cover = '/html/images/cover.png';
	if (exists $googleAlbum->{albumArtRef}) {
		$cover = $googleAlbum->{albumArtRef};
		$cover = Plugins::GoogleMusic::Image->uri($cover);
	}

	my $album = {
		uri => $uri,
		id => $googleAlbum->{albumId},
		name => $name,
		artist => $artist,
		year => $year,
		cover => $cover,
		tracks => [],
	};

	if (exists $googleAlbum->{tracks}) {
		foreach (@{$googleAlbum->{tracks}}) {
			my $track = to_slim_track($_);
			if ($track->{album}->{artist}->{various}) {
				$artist->{various} = 1;
			}
			push @{$album->{tracks}}, $track;
		}
	}

	if (exists $googleAlbum->{description}) {
		$album->{description} = $googleAlbum->{description};
	}

	return $album;
}

# Convert an All Access Google Music artist dictionary to a consistent
# robust artist representation
sub artist_to_slim_artist {
	my $googleArtist = shift;

	my $name = $googleArtist->{name};

	my $uri = 'googlemusic:artist:' . $googleArtist->{artistId};

	my $image = '/html/images/artists.png';
	if (exists $googleArtist->{artistArtRef}) {
		$image = $googleArtist->{artistArtRef};
		$image = Plugins::GoogleMusic::Image->uri($image);
	}

	my $artist = {
		uri => $uri,
		id => $googleArtist->{artistId},
		name => $name,
		image => $image,
		tracks => [],
		albums => [],
		related => [],
	};

	if (exists $googleArtist->{topTracks}) {
		for my $track (@{$googleArtist->{topTracks}}) {
			push @{$artist->{tracks}}, to_slim_track($track);
		}
	}
	if (exists $googleArtist->{albums}) {
		for my $album (@{$googleArtist->{albums}}) {
			push @{$artist->{albums}}, album_to_slim_album($album);
		}
	}
	if (exists $googleArtist->{related_artists}) {
		for my $related (@{$googleArtist->{related_artists}}) {
			push @{$artist->{related}}, artist_to_slim_artist($related);
		}
	}

	if (exists $googleArtist->{artistBio}) {
		$artist->{artistBio} = $googleArtist->{artistBio};
	}

	return $artist;
}

# Get Google Music genres, either parents or child genres
sub getGenres {
	my $uri = shift;

	return unless $prefs->get('all_access_enabled');
	
	my ($parent) = $uri =~ m{^googlemusic:genres:(.*)$}x;

	my $genres;

	if ($genres = $cache->get($uri)) {
		return $genres;
	}

	my $googleGenres;
	$genres = [];

	eval {
		if (Plugins::GoogleMusic::GoogleAPI::get_version() lt '4.1.0') {
			$googleGenres = $googleapi->get_genres($parent)->{genres};
		} else {
			$googleGenres = $googleapi->get_genres($parent);
		}
	};
	if ($@) {
		$log->error("Not able to get genres: $@");
		return $genres;
	}

	for my $genre (@{$googleGenres}) {
		push @{$genres}, genreToSlimGenre($genre);
	}
	
	$cache->set($uri, $genres, $CACHE_TIME);

	return $genres;
}

# Convert an All Access Google Music genre dictionary to a consistent
# robust genre representation
sub genreToSlimGenre {
	my $googleGenre = shift;

	my $uri = 'googlemusic:genre:' . $googleGenre->{id};

	my $image = '/html/images/genres.png';
	if (exists $googleGenre->{images}) {
		$image = $googleGenre->{images}[0]{url};
		$image = Plugins::GoogleMusic::Image->uri($image);
	}

	my $genre = {
		uri => $uri,
		id => $googleGenre->{id},
		name => $googleGenre->{name},
		image => $image,
	};

	if (exists $googleGenre->{children}) {
		$genre->{children} = $googleGenre->{children};
	}
	if (exists $googleGenre->{parentId}) {
		$genre->{parent} = $googleGenre->{parentId};
	}

	$cache->set($uri, $genre, $CACHE_TIME);

	return $genre;
}

# Get all user-created radio stations
sub getStations {
	
	return [] unless $prefs->get('all_access_enabled');
	
	my $stations;
	my $uri = 'googlemusic:stations';

	if ($stations = $cache->get($uri)) {
		return $stations;
	}

	eval {
		$stations = $googleapi->get_all_stations();
	};
	if ($@) {
		$log->error("Not able to get user created radio stations: $@");
		return [];
	}

	$cache->set($uri, $stations, $CACHE_TIME_SHORT);

	return $stations;
}

sub deleteStation {
	my $id = shift;
	
	eval {
		$googleapi->delete_stations($id);
	};
	if ($@) {
		$log->error("Not able to delete radio station $id: $@");
		return;
	}

	# Remove from cache to force reload
	$cache->remove('googlemusic:stations');

	# Return the ID on success
	return $id;
}

# Get a specific genre (from the cache)
sub getGenre {
	my $uri = shift;

	my $genre;

	if ($genre = $cache->get($uri)) {
		return $genre;
	}

	# Not found in the cache. Refresh parent genres.
	my $genres = getGenres('googlemusic:genres');
	# Try again
	if ($genre = $cache->get($uri)) {
		return $genre;
	}

	# Still not found. Must be a child genre.
	my ($id) = $uri =~ m{^googlemusic:genre:(.*)$}x;
	# Search a matching parent and get its childs
	for my $parent (@{$genres}) {
		if ( grep { $_ eq $id } @{$parent->{children}} ) {
			$genres = getGenres($parent->{uri});
			last;
		}
	}
	# Try again
	if ($genre = $cache->get($uri)) {
		return $genre;
	}

	$log->error("Not able to get genre: $uri");

	return;
}

# Change the rating of a track
sub changeRating {
	my ($uri, $rating) = @_;

	return unless $prefs->get('all_access_enabled');

	my ($id) = $uri =~ m{^googlemusic:track:(.*)$}x;
	my $song;

	# Get the Google track info first
	eval {
		$song = $googleapi->get_track_info($id);
	};
	if ($@) {
		$log->error("Not able to get the track info for track ID $id: $@");
		return;
	}

	# Now change the rating value
	$song->{rating} = $rating;

	# And apply it
	eval {
		$song = $googleapi->change_song_metadata($song);
	};
	if ($@) {
		$log->error("Not able to change the song metadata for track ID $id: $@");
		return;
	}

	# TBD: This only updates the track in the cach NOT albums, search
	# results etc.
	# Also need to update our cache. Get it from the cache first.
	my $track = get_track($uri);
	# Change the rating
	$track->{rating} = $rating;
	# And update the cache
	$cache->set($uri, $track, $CACHE_TIME_LONG);

	return;
}

1;
