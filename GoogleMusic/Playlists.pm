package Plugins::GoogleMusic::Playlists;

use strict;
use warnings;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(string);

use Plugins::GoogleMusic::GoogleAPI;
use Plugins::GoogleMusic::Library;
use Plugins::GoogleMusic::AllAccess;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

my $playlists = {};

# Reload and reparse all playlists
sub refresh {
	my $googlePlaylists;

	if (!$googleapi->is_authenticated()) {
		return;
	}

	$playlists = {};

	# Get all user playlists first
	$googlePlaylists = $googleapi->get_all_user_playlist_contents();
	for my $googlePlaylist (@$googlePlaylists) {
		my $playlist = {};
		$playlist->{name} = $googlePlaylist->{name};
		$playlist->{uri} = 'googlemusic:playlist:' . $googlePlaylist->{id};
		$playlist->{tracks} = to_slim_playlist_tracks($googlePlaylist->{tracks});
		$playlists->{$playlist->{uri}} = $playlist;
	}

	# Now get all shared playlists
	$googlePlaylists = $googleapi->get_all_playlists();
	for my $googlePlaylist (@$googlePlaylists) {
		if ($googlePlaylist->{type} eq 'SHARED') {
			my $playlist = {};
			$playlist->{name} = $googlePlaylist->{name};
			$playlist->{uri} = 'googlemusic:playlist:' . $googlePlaylist->{id};
			my $googleTracks = $googleapi->get_shared_playlist_contents($googlePlaylist->{shareToken});
			$playlist->{tracks} = to_slim_playlist_tracks($googleTracks);
			$playlists->{$playlist->{uri}} = $playlist;
		}
	}
	
	return;
}

sub to_slim_playlist_tracks {
	my $googleTracks = shift;
	
	my $tracks = [];

	for my $song (@{$googleTracks}) {
		my $track;
		# Is it an All Access track?
		if ($song->{trackId} =~ '^T') {
			# Already populated?
			if (exists $song->{track}) {
				$track = Plugins::GoogleMusic::AllAccess::to_slim_track($song->{track});
			} else {
				$track = Plugins::GoogleMusic::AllAccess::get_track_by_id($song->{trackId});
			}
		} else {
			$track = Plugins::GoogleMusic::Library::get_track_by_id($song->{trackId});
		}
		if ($track) {
			push @{$tracks}, $track;
		} else {
			$log->error('Not able to lookup playlist track ' . $song->{trackId});
		}
	}

	return $tracks;
}


sub get {
	return [sort {lc($a->{name}) cmp lc($b->{name})} values %$playlists];
}

1;
