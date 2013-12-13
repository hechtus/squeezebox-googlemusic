package Plugins::GoogleMusic::Library;

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use Encode qw(encode_utf8);
use Data::Dumper;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(string);

use Plugins::GoogleMusic::GoogleAPI;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

my $tracks;
my $albums;
my $artists;

# Reload and reparse your music collection
sub refresh {
	my $songs;
	my ($track, $album, $artist);

	if (!$googleapi->is_authenticated()) {
		return;
	}
	
	$tracks = {};
	$albums = {};
	$artists = {};

	$songs = $googleapi->get_all_songs();

	for my $song (@{$songs}) {
		$track = to_slim_track($song);
		$tracks->{$track->{uri}} = $track;

		$album = to_slim_album($song);
		$albums->{$album->{uri}} = $album;

		$artist = to_slim_artist($song);
		$artists->{$artist->{uri}} = $artist;
		$artist = to_slim_album_artist($song);
		$artists->{$artist->{uri}} = $artist;
	}
}

sub search {
	my $query = shift;

	if (!$query) {
		$query = {};
	}

	my @result = values(%$tracks);
	my $albums = [];
	my $artists = [];

	return (\@result, $albums, $artists);
}

sub search_tracks {
	my $query = shift;

	if (!$query) {
		$query = {};
	}

	my $result = $tracks;


}

sub get_track {
	my $uri = shift;

	return $tracks->{$uri};
}

# Convert a Google Music Song dictionary to a consistent
# robust track representation
sub to_slim_track {
	my $song = shift;
	my $cover = '/html/images/cover.png';

	if (exists $song->{albumArtRef}) {
		$cover = $song->{albumArtRef}[0]{url};
	}

	return {
		uri => 'googlemusic:track:' . $song->{id},
		title => $song->{title},
		album => $song->{album},
		artist => $song->{artist},
		year => $song->{year} || 0,
		cover => Plugins::GoogleMusic::Image->uri($cover),
		secs => $song->{durationMillis} / 1000,
		bitrate => 320,
		genre => $song->{genre},
		filesize => $song->{estimatedSize},
		trackNumber => $song->{trackNumber} || 1,
		discNumber => $song->{discNumber} || 1,
	}
}

# Convert a Google Music Song dictionary to a consistent
# robust album representation
sub to_slim_album {
	my $song = shift;
	my $cover = '/html/images/cover.png';

	if (exists $song->{albumArtRef}) {
		$cover = $song->{albumArtRef}[0]{url};
	}

	my $artist = $song->{albumArtist} || $song->{artist};
	my $year = $song->{year} || 0;

	# Better create an ID by ourself. IDs in My Library are not
	# consistent and are not always present
	my $id = _create_id($artist . $song->{album} . $year);

	return {
		uri => 'googlemusic:album:' . $id,
		name => $song->{album},
		artist => $artist,
		year => $year,
		cover => Plugins::GoogleMusic::Image->uri($cover),
	}
}

# Convert a Google Music Song dictionary to a consistent
# robust artist representation
sub to_slim_artist {
	my $song = shift;
	my $image = '/html/images/artists.png';

	if (exists $song->{artistArtRef}) {
		$image = $song->{artistArtRef}[0]{url};
	}

	my $name = $song->{artist};
	
	# Better create an ID by ourself. IDs in My Library are not
	# consistent and are not always present
	my $id = _create_id($name);

	return {
		uri => 'googlemusic:artist:' . $id,
		name => $name,
		image => Plugins::GoogleMusic::Image->uri($image),
	}
}

# Convert a Google Music Song dictionary to a consistent
# robust album artist representation
sub to_slim_album_artist {
	my $song = shift;
	my $image = '/html/images/artists.png';

	# Check to see if this album is a compilation from various
	# artists. The Google Music webinterface also shows a 'various'
	# artist in my library instead of all seperate artists.. which
	# should justify this functionality
	my $various = index(lc($song->{artist}), lc($song->{albumArtist} || '')) == -1;

	if (exists $song->{artistArtRef} and !$various) {
		$image = $song->{artistArtRef}[0]{url};
	}
	
	# In one test case (the band 'Poliça') GoogleMusic messed up the
	# 'artist' is sometime lowercase, where the 'albumArtist' is
	# uppercase the albumArtist is the most consistent so take that or
	# else we will see multiple entries in the Artists listing (lower
	# + upper case)
	my $name = $song->{albumArtist} || $song->{artist};
	
	# Better create an ID by ourself. IDs in My Library are not
	# consistent and are not always present
	my $id = _create_id($name);

	return {
		uri => 'googlemusic:artist:' . $id,
		name => $name,
		image => Plugins::GoogleMusic::Image->uri($image),
	}
}

sub _create_id {
	my $str = shift;

	return md5_hex(encode_utf8($str));
}

1;
