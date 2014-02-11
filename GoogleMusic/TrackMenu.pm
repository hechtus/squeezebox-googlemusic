package Plugins::GoogleMusic::TrackMenu;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Prefs;


my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');

my %sortMap = (
	'album' => \&_sortAlbum,
	'artistalbum' => \&_sortArtistAlbum,
	'artistyearalbum' => \&_sortArtistYearAlbum,
	'yearalbum' => \&_sortYearAlbum,
	'yearartistalbum' => \&_sortYearArtistAlbum,
);

sub menu {
	my ($client, $callback, $args, $tracks, $opts) = @_;

	my @items;

	if ($opts->{sortByTrack}) {
		@$tracks = sort _sortTrack @$tracks;
	} elsif ($opts->{sortTracks}) {
		my $sortMethod = $opts->{all_access} ?
			$prefs->get('all_access_album_sort_method') :
			$prefs->get('my_music_album_sort_method');
		if (exists $sortMap{$sortMethod}) {
			@$tracks = sort {$sortMap{$sortMethod}->()} @$tracks;
		}
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

sub _sortTrack {
	return ($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) or
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortAlbum {
	return lc($a->{album}->{name}) cmp lc($b->{album}->{name}) or
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) or
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortArtistAlbum {
	return lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) or
		lc($a->{album}->{name}) cmp lc($b->{album}->{name}) or
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) or
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortArtistYearAlbum {
	return lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) or
		($b->{year} || -1) <=> ($a->{year} || -1) or
		lc($a->{album}->{name}) cmp lc($b->{album}->{name}) or
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) or
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortYearAlbum {
	return ($b->{year} || -1) <=> ($a->{year} || -1) or
		lc($a->{album}->{name}) cmp lc($b->{album}->{name}) or
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) or
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortYearArtistAlbum {
	return ($b->{year} || -1) <=> ($a->{year} || -1) or
		lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) or
		lc($a->{album}->{name}) cmp lc($b->{album}->{name}) or
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) or
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

1;
