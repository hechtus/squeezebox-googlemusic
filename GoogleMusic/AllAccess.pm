package Plugins::GoogleMusic::AllAccess;

use strict;
use warnings;

use Tie::Cache::LRU;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;

use Plugins::GoogleMusic::GoogleAPI;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

# Cache track, album, and artist translation results for one hour
use Readonly;
Readonly my $CACHE_TIME => 3600;
tie my %cache, 'Tie::Cache::LRU', 100;

# Convert an All Access Google Music Song dictionary to a consistent
# robust track representation
sub to_slim_track {
	my $song = shift;

	my $uri = 'googlemusic:track:' . $song->{storeId};
	if ($cache{$uri} && (time() - $cache{$uri}->{time}) < $CACHE_TIME) {
		return $cache{$uri}->{data};
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
	};

	# Add to the cache
	$cache{$uri} = {
		data => $track,
		time => time(),
	};

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

	my $uri;
	my $name = $song->{artist};

	# TODO: Sometimes the array has multiple entries
	if (scalar $song->{artistId}) {
		$uri = 'googlemusic:artist:' . $song->{artistId}[0];
	} else {
		$uri = 'googlemusic:artist:unknown';
	}

	my $image = '/html/images/artists.png';
	if (exists $song->{artistArtRef}) {
		$image = $song->{artistArtRef}[0]{url};
		$image = Plugins::GoogleMusic::Image->uri($image);
	}

	my $artist = {
		uri => $uri,
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
		name => $name,
		various => $various,
		image => $image,
	};

	return $artist;
}

sub get_track {
	my $uri = shift;

	return unless $prefs->get('all_access_enabled');

	if ($cache{$uri} && (time() - $cache{$uri}->{time}) < $CACHE_TIME) {
		return $cache{$uri}->{data};
	}

	my ($id) = $uri =~ m{^googlemusic:track:(.*)$}x;
	my $song;

	eval {
		$song = $googleapi->get_track_info($id);
	};
	if ($@) {
		$log->error("Not able to get the track info for track ID $id: $@");
		return;
	}

	return to_slim_track($song);
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
	if ($cache{$uri} && (time() - $cache{$uri}->{time}) < $CACHE_TIME) {
		return $cache{$uri}->{data};
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
	$cache{$uri} = {
		data => $result,
		time => time(),
	};

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

	if ($cache{$uri} && (time() - $cache{$uri}->{time}) < $CACHE_TIME) {
		return $cache{$uri}->{data};
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
	$cache{$uri} = {
		data => $artist,
		time => time(),
	};

	return $artist;
}

sub get_artist_image {
	my $uri = shift;

	return unless $prefs->get('all_access_enabled');

	# First try to get the image from the artist cache
	if ($cache{$uri} && (time() - $cache{$uri}->{time}) < $CACHE_TIME) {
		return $cache{$uri}->{data}->{image};
	}

	my ($id) = $uri =~ m{^googlemusic:artist:(.*)$}x;

	my $imageuri = 'googlemusic:artistimage:' . $id;

	if ($cache{$imageuri} && (time() - $cache{$imageuri}->{time}) < $CACHE_TIME) {
		return $cache{$imageuri}->{data};
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
	$cache{$imageuri} = {
		data => $image,
		time => time(),
	};

	return $image;
}

# Get information for an album
sub get_album_info {
	my $uri = shift;

	return unless $prefs->get('all_access_enabled');

	if ($cache{$uri} && (time() - $cache{$uri}->{time}) < $CACHE_TIME) {
		return $cache{$uri}->{data};
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
	$cache{$uri} = {
		data => $album,
		time => time(),
	};

	return $album;
}

# Convert an All Access Google album dictionary to a consistent
# robust album representation
sub album_to_slim_album {
	my $googleAlbum = shift;

	# TODO: Sometimes the array has multiple entries
	my $artist = {
		uri => 'googlemusic:artist:' . $googleAlbum->{artistId}[0],
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

# TBD: We could also store everything else in this cache
my $genreCache = Slim::Utils::Cache->new('googlemusic', 3);

# Get Google Music genres, either parents or child genres
sub getGenres {
	my $uri = shift;

	return unless $prefs->get('all_access_enabled');
	
	my ($parent) = $uri =~ m{^googlemusic:genres:(.*)$}x;

	my $genres;

	if ($genres = $genreCache->get($uri)) {
		return $genres;
	}

	my $googleGenres;
	$genres = [];

	eval {
		$googleGenres = $googleapi->get_genres($parent);
	};
	if ($@) {
		$log->error("Not able to get genres: $@");
		return $genres;
	}

	for my $genre (@{$googleGenres->{genres}}) {
		push @{$genres}, genreToSlimGenre($genre);
	}
	
	$genreCache->set($uri, $genres, $CACHE_TIME);

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

	$genreCache->set($uri, $genre, $CACHE_TIME);

	return $genre;
}

# Get a specific genre (from the cache)
sub getGenre {
	my $uri = shift;

	my $genre;

	if ($genre = $genreCache->get($uri)) {
		return $genre;
	}

	# Not found in the cache. Refresh parent genres.
	my $genres = getGenres('googlemusic:genres');
	# Try again
	if ($genre = $genreCache->get($uri)) {
		return $genre;
	}

	# Still not found. Must be a child genre.
	my ($id) = $uri =~ m{^googlemusic:genre:(.*)$}x;
	# Search a matching parent and get its childs
	for my $parent (@{$genres}) {
		if ( grep { $_ eq $id } @{$parent->{children}} ) {
			$genres = getGenres($parent->{uri});
		}
	}
	# Try again
	if ($genre = $genreCache->get($uri)) {
		return $genre;
	}

	$log->error("Not able to get genre: $uri");

	return;
}

1;
