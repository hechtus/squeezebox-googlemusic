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

sub feed {
	my ($client, $callback, $args, $tracks, $opts) = @_;

	return $callback->(menu($client, $args, $tracks, $opts));
}

sub menu {
	my ($client, $args, $tracks, $opts) = @_;

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

	for my $track (@{$tracks}) {
		push @items, _showTrack($client, $track, $opts);
	}

	if (!scalar @items) {
		push @items, {
			name => cstring($client, 'EMPTY'),
			type => 'text',
		};
	}

	return {
		items => \@items,
	};
}

sub _showTrack {
	my ($client, $track, $opts) = @_;

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
	};

	# Play all tracks in a list. Useful for albums and playlists.
	if ($opts->{playall}) {
		$item->{playall} = 1;
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
