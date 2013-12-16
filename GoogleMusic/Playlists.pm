package Plugins::GoogleMusic::Playlists;

use strict;
use warnings;

use Data::Dumper;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(string);

use Plugins::GoogleMusic::GoogleAPI;

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
		$playlist->{tracks} = [];
		for my $song (@{$googlePlaylist->{tracks}}) {
			my $track = Plugins::GoogleMusic::Library::get_track_by_id($song->{trackId});
			if ($track) {
				push @{$playlist->{tracks}}, $track;
			} else {
				$log->error('Not able to find track ' . $song->{trackId} .
							' for playlist ' . $playlist->{name} .
							' in your library');
			}
		}
		$playlists->{$playlist->{uri}} = $playlist;
	}

	# Now get all shared playlists
	$googlePlaylists = $googleapi->get_all_playlists();
	for my $googlePlaylist (@$googlePlaylists) {
		if ($googlePlaylist->{type} eq 'SHARED') {
			my $playlist = {};
			$playlist->{name} = $googlePlaylist->{name};
			$playlist->{uri} = 'googlemusic:playlist:' . $googlePlaylist->{id};
			$playlist->{tracks} = [];
			my $googleTracks = $googleapi->get_shared_playlist_contents(
				$googlePlaylist->{shareToken});
			print Dumper $googleTracks;
			for my $song (@{$googleTracks}) {
				# TODO: We don't need to lookup. We can simply all-access-translate $song->{track}
				my $track = Plugins::GoogleMusic::Library::get_track_by_id($song->{trackId});
				if ($track) {
					push @{$playlist->{tracks}}, $track;
				}
			}
			$playlists->{$playlist->{uri}} = $playlist;
		}
	}
	
	return;
}

sub get {
	return [sort {lc($a->{name}) cmp lc($b->{name})} values %$playlists];
}

1;
