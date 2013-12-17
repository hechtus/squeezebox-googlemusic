package Plugins::GoogleMusic::AllAccess;

use strict;
use warnings;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(string);

use Plugins::GoogleMusic::GoogleAPI;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

# Convert an All Access Google Music Song dictionary to a consistent
# robust track representation
sub to_slim_track {
	my $song = shift;

	my $uri = 'googlemusic:track:' . $song->{storeId};

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

	my $name = $song->{artist};
	
	my $uri = 'googlemusic:artist:' . $song->{artistId}[0];

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
	my $various = index(lc($song->{artist}), lc($song->{albumArtist} || '')) == -1;
	if (exists $song->{artistArtRef} and not $various) {
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

sub get_track {
	# TODO: We need to cache them ...
	return;
}

sub get_track_by_id {
	# TODO: We need to cache them ...
	return;
}

1;
