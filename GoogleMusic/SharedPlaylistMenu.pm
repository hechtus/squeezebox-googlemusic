package Plugins::GoogleMusic::SharedPlaylistMenu;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Prefs;

use Plugins::GoogleMusic::TrackMenu;
use Plugins::GoogleMusic::Playlists;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

sub feed {
	my ($client, $callback, $args, $playlists, $opts) = @_;

	return $callback->(menu($client, $args, $playlists, $opts));
}

sub menu {
	my ($client, $args, $playlists, $opts) = @_;

	my @items;

	for my $playlist (@{$playlists}) {
		push @items, _showPlaylist($client, $args, $playlist, $opts);
	}

	if (!scalar @items) {
		push @items, {
			name => cstring($client, 'EMPTY'),
			type => 'text',
		}
	}

	return {
		items => \@items,
	};
}

sub _showPlaylist {
	my ($client, $args, $playlist, $opts) = @_;

	my $item = {
		name  => $playlist->{name},
		line1 => $playlist->{name},
		cover => $playlist->{cover},
		image => $playlist->{cover},
		type  => 'playlist',
		url   => \&_playlistTracks,
		passthrough => [ $playlist , { all_access => 1, showArtist => 1, showAlbum => 1, playall => 1 } ],
	};

	if ($playlist->{owner}) {
		$item->{name2} = cstring($client, 'BY') . ' ' . $playlist->{owner};
		$item->{line2} = cstring($client, 'BY') . ' ' . $playlist->{owner};
	}

	return $item;
}

sub _playlistTracks {
	my ($client, $callback, $args, $playlist, $opts) = @_;

	my $googleTracks;

	eval {
		$googleTracks = $googleapi->get_shared_playlist_contents($playlist->{id});
	};
	if ($@) {
		$log->error("Not able to get shared playlist contents: $@");
		$googleTracks = [];
	}

	my $tracks = Plugins::GoogleMusic::Playlists::to_slim_playlist_tracks($googleTracks);

	my $trackItems = Plugins::GoogleMusic::TrackMenu::menu($client, $args, $tracks, $opts);
	
	return $callback->($trackItems);
}

1;
