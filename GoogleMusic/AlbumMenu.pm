package Plugins::GoogleMusic::AlbumMenu;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Plugins::GoogleMusic::TrackMenu;
use Plugins::GoogleMusic::AlbumInfo;


my $log = logger('plugin.googlemusic');


sub menu {
	my ($client, $callback, $args, $albums, $opts) = @_;

	my @items;

	if ($opts->{sortAlbums}) {
		@$albums = sort { lc($a->{artist}->{name}) cmp lc($b->{artist}->{name}) or
						 ($b->{year} || -1) <=> ($a->{year} || -1) or
						  lc($a->{name}) cmp lc($b->{name})
		} @$albums;
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

	my %actions = (
		commonVariables => [uri => 'uri'],
		info => {
			command     => ['googlemusicalbuminfo', 'items'],
		},
		items => {
			command     => ['googlemusicbrowse', 'items'],
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
	);
	$actions{playall} = $actions{play};
	$actions{addall} = $actions{add};

	# TODO: For googlemusicbrowse for artists we need to add the
	#       artist image here.
	$callback->({
		items => \@items,
		actions => \%actions,
	});

	return;
}

sub _showAlbum {
	my ($client, $args, $album, $opts) = @_;

	my $albumYear = $album->{year} || " ? ";

	my $item = {
		name  => $album->{name} . " (" . $albumYear . ")",
		name2  => $album->{artist}->{name},
		line1 => $album->{name} . " (" . $albumYear . ")",
		line2 => $album->{artist}->{name},
		cover => $album->{cover},
		image => $album->{cover},
		type  => 'playlist',
		url   => \&_albumTracks,
		uri   => $album->{uri},
		hasMetadata   => 'album',
		passthrough => [ $album , { all_access => $opts->{all_access}, playall => 1, playall_uri => $album->{uri}, sortByTrack => 1 } ],
	};

	if ($args->{wantMetadata}) {
		my $feed = Plugins::GoogleMusic::AlbumInfo->menu($client, $album->{uri}, $album);
		$item->{albumData} = $feed->{items} if $feed;
		$item->{albumInfo} = {
			info => {
				command => ['googlemusicalbuminfo', 'items'], 
				fixedParams => { uri => $album->{uri} }
			},
		};
	}

	return $item;
}

sub _albumTracks {
	my ($client, $callback, $args, $album, $opts) = @_;

	my $tracks;

	# All Access or All Access album?
	if ($opts->{all_access} || $album->{uri} =~ '^googlemusic:album:B') {
		my $info = Plugins::GoogleMusic::AllAccess::get_album_info($album->{uri});
		if ($info) {
			$tracks = $info->{tracks};
		} else {
			$tracks = [];
		}
	} else {
		$tracks = $album->{tracks};
	}

	Plugins::GoogleMusic::TrackMenu::menu($client, $callback, $args, $tracks, $opts);

	return;
}

1;
