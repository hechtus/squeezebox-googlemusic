package Plugins::GoogleMusic::Playlists;

use strict;
use warnings;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(cstring);

use Plugins::GoogleMusic::GoogleAPI;
use Plugins::GoogleMusic::Library;
use Plugins::GoogleMusic::AllAccess;
use Plugins::GoogleMusic::TrackMenu;


my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

my $playlists = {};

sub feed {
	my ($client, $callback, $args) = @_;

	my @items;

	foreach (sort {lc($a->{name}) cmp lc($b->{name})} values %$playlists) {
		push @items, _showPlaylist($client, $_);
	}

	if (!scalar @items) {
		push @items, {
			'name' => cstring($client, 'EMPTY'),
			'type' => 'text',
		}

	}

	$callback->({
		items => \@items,
	});

	return;
}

sub _showPlaylist {
	my ($client, $playlist) = @_;

	my $item = {
		name => $playlist->{'name'},
		type => 'playlist',
		url => \&Plugins::GoogleMusic::TrackMenu::feed,
		passthrough => [$playlist->{tracks}, { showArtist => 1, showAlbum => 1, playall => 1 }],
	};

	return $item;
}

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
		if (exists $googlePlaylist->{type} && $googlePlaylist->{type} eq 'SHARED') {
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


1;
