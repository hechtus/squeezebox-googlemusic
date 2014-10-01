package Plugins::GoogleMusic::AlbumMenu;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Prefs;

use Plugins::GoogleMusic::TrackMenu;

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
	my ($client, $callback, $args, $albums, $opts) = @_;

	return $callback->(menu($client, $args, $albums, $opts));
}

sub menu {
	my ($client, $args, $albums, $opts) = @_;

	my @items;

	if ($opts->{sortAlbums}) {
		my $sortMethod = $opts->{all_access} ?
			$prefs->get('all_access_album_sort_method') :
			$prefs->get('my_music_album_sort_method');
		if (exists $sortMap{$sortMethod}) {
			@$albums = sort {$sortMap{$sortMethod}->()} @$albums;
		}
	}

	for my $album (@{$albums}) {
		push @items, _showAlbum($client, $args, $album, $opts);
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

sub _showAlbum {
	my ($client, $args, $album, $opts) = @_;

	my $item = {
		name  => $album->{name},
		name2  => $album->{artist}->{name},
		line1 => $album->{name},
		line2 => $album->{artist}->{name},
		cover => $album->{cover},
		image => $album->{cover},
		type  => 'playlist',
		url   => \&_albumTracks,
		hasMetadata   => 'album',
		passthrough => [ $album , { all_access => $opts->{all_access}, playall => 1, sortByTrack => 1 } ],
		albumData => [
			{ type => 'link', label => 'ARTIST', name => $album->{artist}->{name} },
			{ type => 'link', label => 'ALBUM', name => $album->{name} },
		],
	};

	# Show the album year only if available
	if ($album->{year}) {
		$item->{name} .= " (" . $album->{year} . ")";
		$item->{line1} .= " (" . $album->{year} . ")";
		push @{$item->{albumData}}, { type => 'link', label => 'YEAR', name => $album->{year} };
	}

	# If the albums are sorted by name add a text key to easily jump
	# to albums on squeezeboxes
	if ($opts->{sortAlbums}) {
		my $sortMethod = $opts->{all_access} ?
			$prefs->get('all_access_album_sort_method') :
			$prefs->get('my_music_album_sort_method');
		if ($sortMethod eq 'album') {
			$item->{textkey} = substr($album->{name}, 0, 1);
		}
	}

	return $item;
}

sub _albumInfo {
	my ($client, $args, $album, $opts) = @_;

	my $albumInfo = [];

	if ($album->{artist}->{id}) {
		push @$albumInfo, {
			label => 'ARTIST',
			name  => $album->{artist}->{name},
			image => '/html/images/artists.png',
			url   => \&Plugins::GoogleMusic::ArtistMenu::_artistMenu,
			passthrough => [ $album->{artist}, { all_access => $opts->{all_access} } ],
		};
	} else {
		push @$albumInfo, {
			type  => 'text',
			label => 'ARTIST',
			name  => $album->{artist}->{name},
			image => '/html/images/artists.png',
		};
	}

	# In the OrangeSqueeze app images are not shown when setting to
	# text which is definitely a bug of the App.
	push @$albumInfo, {
		type  => 'text',
		label => 'YEAR',
		name  => $album->{year},
		image => '/html/images/years.png',
	} if $album->{year};

	push @$albumInfo, {
		name => cstring($client, "PLUGIN_GOOGLEMUSIC_ABOUT_THIS_ALBUM"),
		items => [{
			name => $album->{description},
			type => 'text',
			wrap => 1,
		}],
		image => '/html/images/albums.png',
	} if $album->{description};

	push @$albumInfo, {
		name  => cstring($client, "PLUGIN_GOOGLEMUSIC_START_RADIO"),
		url => \&Plugins::GoogleMusic::Radio::startRadioFeed,
		passthrough => [ $album->{storeId} ? 'googlemusic:album:' .  $album->{storeId} : $album->{uri} ],
		image => '/html/images/playlists.png',
		nextWindow => 'nowPlaying',
	} if $prefs->get('all_access_enabled') && ($album->{storeId} || $album->{uri} =~ '^googlemusic:album:B');

	return $albumInfo;
}

sub _albumTracks {
	my ($client, $callback, $args, $album, $opts) = @_;

	my $tracks;

	my $info = Plugins::GoogleMusic::Library::get_album($album->{uri});
	if ($info) {
		$tracks = $info->{tracks};
		$opts->{showArtist} = $info->{artist}->{various};
	} else {
		$tracks = [];
	}

	my $trackItems = Plugins::GoogleMusic::TrackMenu::menu($client, $args, $tracks, $opts);
	
	push (@{$trackItems->{items}}, @{_albumInfo($client, $args, $info, $opts)});
	
	return $callback->($trackItems);
}

sub _sortAlbum {
	return lc($a->{name}) cmp lc($b->{name});
}

sub _sortArtistAlbum {
	return lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) ||
		lc($a->{name}) cmp lc($b->{name});
}

sub _sortArtistYearAlbum {
	return lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) ||
		($b->{year} || -1) <=> ($a->{year} || -1) ||
		lc($a->{name}) cmp lc($b->{name});
}

sub _sortYearAlbum {
	return ($b->{year} || -1) <=> ($a->{year} || -1) ||
		lc($a->{name}) cmp lc($b->{name});
}

sub _sortYearArtistAlbum {
	return ($b->{year} || -1) <=> ($a->{year} || -1) ||
		lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) ||
		lc($a->{name}) cmp lc($b->{name});
}

1;
