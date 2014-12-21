package Plugins::GoogleMusic::TrackMenu;

use strict;
use warnings;

use List::Util qw(min);

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
	} elsif ($opts->{sortByCreation}) {
		# Sort and limit the number of tracks
		@$tracks = sort _sortCreation @$tracks;
		@$tracks = @$tracks[0..min($#$tracks, 249)];
	}

	for my $track (@{$tracks}) {
		push @items, _showTrack($client, $args, $track, $opts);
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
	my ($client, $args, $track, $opts) = @_;

	my $item = {
		name     => $track->{title},
		line1    => $track->{title},
		image    => $track->{cover},
		secs     => $track->{secs},
		duration => $track->{secs},
		bitrate  => $track->{bitrate},
		genre    => $track->{genre},
		play     => $track->{uri},
		items    => _trackInfo($client, $args, $track, $opts),
		on_select => 'play',
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

sub _trackInfo {
	my ($client, $args, $track, $opts) = @_;

	my $trackInfo = [];

	# Refetch the rating for the track. It is possibly out of
	# date. Should be fast as it comes from our cache.
	my $rating = Plugins::GoogleMusic::Library::get_track($track->{uri})->{rating};

	push @$trackInfo, {
		name => cstring($client, ($rating >= 4) ? 'PLUGIN_GOOGLEMUSIC_UNLIKE' : 'PLUGIN_GOOGLEMUSIC_LIKE'),
		type => 'link',
		url => \&Plugins::GoogleMusic::Plugin::like,
		passthrough => [ $track->{uri}, ($rating >= 4) ? 0 : 5 ],
		nextWindow => 'parent',
		forceRefresh => 1,
		favorites => 0,
	};
	push @$trackInfo, {
		name => cstring($client, ($rating != 0 && $rating < 3) ? "PLUGIN_GOOGLEMUSIC_DONT_DISLIKE" : "PLUGIN_GOOGLEMUSIC_DISLIKE"),
		type => 'link',
		url => \&Plugins::GoogleMusic::Plugin::dislike,
		passthrough => [ $track->{uri}, ($rating != 0 && $rating < 3) ? 0 : 1 ],
		nextWindow => 'parent',
		forceRefresh => 1,
		favorites => 0,
	};

	push @$trackInfo, {
		type  => 'link',
		label => 'ALBUM',
		name  => $track->{album}->{name},
		url   => \&Plugins::GoogleMusic::AlbumMenu::_albumTracks,
		passthrough => [ $track->{album}, { all_access => $opts->{all_access}, playall => 1, sortByTrack => 1 } ],
	};

	push @$trackInfo, {
		type  => 'link',
		label => 'ARTIST',
		name  => $track->{artist}->{name},
		url   => \&Plugins::GoogleMusic::ArtistMenu::_artistMenu,
		passthrough => [ $track->{artist}, { all_access => $opts->{all_access} } ],
	};

	push @$trackInfo, {
		type  => 'text',
		label => 'TITLE',
		name  => $track->{title},
	};

	push @$trackInfo, {
		name  => cstring($client, "PLUGIN_GOOGLEMUSIC_START_RADIO"),
		url => \&Plugins::GoogleMusic::Radio::startRadioFeed,
		passthrough => [ $track->{storeId} ? 'googlemusic:track:' .  $track->{storeId} : $track->{uri} ],
		nextWindow => 'nowPlaying',
	} if $prefs->get('all_access_enabled');

	push @$trackInfo, {
		type  => 'text',
		label => 'TRACK_NUMBER',
		name  => $track->{trackNumber},
	};

	if (my $year = ($track->{year} || $track->{album}->{year})) {
		push @$trackInfo, {
			type  => 'text',
			label => 'YEAR',
			name  => $year,
		};
	}

	push @$trackInfo, {
		type  => 'text',
		label => 'GENRE',
		name  => $track->{genre},
	};

	push @$trackInfo, {
		type  => 'text',
		label => 'LENGTH',
		name  => sprintf('%s:%02s', int($track->{secs} / 60), $track->{secs} % 60),
	};

	return $trackInfo;
}

sub _sortTrack {
	return ($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) ||
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortAlbum {
	return lc($a->{album}->{name}) cmp lc($b->{album}->{name}) ||
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) ||
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortArtistAlbum {
	return lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) ||
		lc($a->{album}->{name}) cmp lc($b->{album}->{name}) ||
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) ||
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortArtistYearAlbum {
	return lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) ||
		($b->{year} || -1) <=> ($a->{year} || -1) ||
		lc($a->{album}->{name}) cmp lc($b->{album}->{name}) ||
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) ||
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortYearAlbum {
	return ($b->{year} || -1) <=> ($a->{year} || -1) ||
		lc($a->{album}->{name}) cmp lc($b->{album}->{name}) ||
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) ||
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortYearArtistAlbum {
	return ($b->{year} || -1) <=> ($a->{year} || -1) ||
		lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) ||
		lc($a->{album}->{name}) cmp lc($b->{album}->{name}) ||
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) ||
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

sub _sortCreation {
	# Sort the tracks by the creation timestamp (in seconds) in the
	# reverse order. Also sort individual albums by the disc/track
	# number to get the same result as with the Google web and mobile
	# interface.
	return ($b->{creationTimestamp} / 1000000) <=> ($a->{creationTimestamp} / 1000000) ||
		lc($a->{album}->{name}) cmp lc($b->{album}->{name}) ||
		($a->{discNumber} || -1) <=> ($b->{discNumber} || -1) ||
		($a->{trackNumber}|| -1)  <=> ($b->{trackNumber} || -1);
}

1;
