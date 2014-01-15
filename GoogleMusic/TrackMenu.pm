package Plugins::GoogleMusic::TrackMenu;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);


my $log = logger('plugin.googlemusic');


sub menu {
	my ($client, $callback, $args, $tracks, $opts) = @_;

	my @items;

	if ($opts->{sortByTrack}) {
		@$tracks = sort { ($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) or
						  ($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1)
		} @$tracks;
	} elsif ($opts->{sortTracks}) {
		@$tracks = sort { lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) or
						 ($b->{year} || -1)  <=> ($a->{year} || -1) or
						 lc(($a->{name} || '')) cmp lc(($b->{name} || ''))  or
						 ($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) or
						 ($a->{trackNumber} || -1)  <=> ($b->{trackNumber} || -1)
		} @$tracks;
	}

	my $index = 0;
	for my $track (@{$tracks}) {
		push @items, _showTrack($client, $track, $index++, $opts);
	}

	if (!scalar @items) {
		push @items, {
			name => cstring($client, 'EMPTY'),
			type => 'text',
		};
	}

	my %actions = (
		commonVariables => [play_index => 'play_index', uri => 'url'],
		info => {
			command     => ['googlemusictrackinfo', 'items'],
		},
		play => {
			command     => ['googlemusicplaylistcontrol'],
			fixedParams => {cmd => 'load'},
		},
		add => {
			command     => ['googlemusicplaylistcontrol'],
			fixedParams => {cmd => 'add'},
		},
		insert => {
			command     => ['googlemusicplaylistcontrol'],
			fixedParams => {cmd => 'insert'},
		},
		playall => {
			command     => ['googlemusicplaylistcontrol'],
			fixedParams => {cmd => 'load'},
			variables   => [play_index => 'play_index', uri => 'playall_uri'],
		},
		addall => {
			command     => ['googlemusicplaylistcontrol'],
			fixedParams => {cmd => 'add'},
			variables   => [play_index => 'play_index', uri => 'playall_uri'],
		},
	);

	# TODO: For googlemusicbrowse for albums we need to add albumData,
	#       albumInfo, and cover here. For this purpose we could pass
	#       wantMetadata and an album URI. A good starting point is
	#       Slim::Menu::BrowseLibrary::_tracks()
	$callback->({
		items => \@items,
		actions => \%actions,
	});

	return;
}

sub _showTrack {
	my ($client, $track, $index, $opts) = @_;

	my $item = {
		name     => $track->{title},
		line1    => $track->{title},
		url      => $track->{uri},
		image    => $track->{cover},
		secs     => $track->{secs},
		duration => $track->{secs},
		bitrate  => $track->{bitrate},
		genre    => $track->{genre},
		type     => 'audio',
		play     => $track->{uri},
		play_index => $index,
	};

	# Play all tracks in a list. Useful for albums and playlists.
	if ($opts->{playall}) {
		$item->{playall} = 1;
		$item->{playall_uri} = $opts->{playall_uri};
	}

	if ($opts->{showArtist}) {
		$item->{name} .= " " . cstring($client, 'BY') . " " . $track->{artist}->{name};
		$item->{line2} = $track->{artist}->{name};
	}

	if ($opts->{showAlbum}) {
		$item->{name} .= " \x{2022} " . $track->{album}->{name};
		if ($item->{line2}) {
			$item->{line2} .= " \x{2022} " . $track->{album}->{name};
		} else {
			$item->{line2} = $track->{album}->{name};
		}
	}

	return $item;
}

1;
