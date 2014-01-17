package Plugins::GoogleMusic::ArtistMenu;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Plugins::GoogleMusic::TrackMenu;
use Plugins::GoogleMusic::AlbumMenu;


my $log = logger('plugin.googlemusic');


sub menu {
	my ($client, $callback, $args, $artists, $opts) = @_;

	my @items;

	if ($opts->{sortArtists}) {
		@$artists = sort { lc($a->{name}) cmp lc($b->{name}) } @$artists;
	}

	for my $artist (@{$artists}) {
		push @items, _showArtist($client, $artist, $opts);
	}

	if (!scalar @items) {
		push @items, {
			name => cstring($client, 'EMPTY'),
			type => 'text',
		}
	}

	$callback->({
		items => \@items,
	});

	return;
}

sub _showArtist {
	my ($client, $artist, $opts) = @_;

	my $item = {
		name => $artist->{name},
		image => $artist->{image},
		type => 'link',
		url => \&_artistMenu,
		passthrough => [ $artist, $opts ],
		itemActions => {
			allAvailableActionsDefined => 1,
			items => {
				command     => ['googlemusicbrowse', 'items'],
				fixedParams => { uri => $artist->{uri} },
			},
		},
	};

	return $item;
}


sub _artistMenu {
	my ($client, $callback, $args, $artist, $opts) = @_;

	if ($opts->{all_access} || $artist->{uri} =~ '^googlemusic:artist:A') {
		# TODO Error handling
		my $info = Plugins::GoogleMusic::AllAccess::get_artist_info($artist->{uri});

		if ($opts->{mode}) {
			if ($opts->{mode} eq 'albums') {
				Plugins::GoogleMusic::AlbumMenu::menu($client, $callback, $args, $info->{albums}, $opts);
				return;
			} elsif ($opts->{mode} eq 'tracks') {
				Plugins::GoogleMusic::TrackMenu::menu($client, $callback, $args, $info->{tracks}, { all_access => 1, showArtist => 1, showAlbum => 1, playall => 1, playall_uri => $artist->{uri} });
				return;
			} elsif ($opts->{mode} eq 'artists') {
				Plugins::GoogleMusic::ArtistMenu::menu($client, $callback, $args, $info->{related}, { } );
				return;
			}
		}

		my @items = ( {
			name => cstring($client, "ALBUMS") . " (" . scalar @{$info->{albums}} . ")",
			type => 'link',
			url => \&Plugins::GoogleMusic::AlbumMenu::menu,
			itemActions => {
				items => {
					command     => ['googlemusicbrowse', 'items'],
					fixedParams => { mode => 'albums', uri => $artist->{uri} },
				},
			},
			passthrough => [ $info->{albums}, $opts ],
		}, {
			name => cstring($client, "PLUGIN_GOOGLEMUSIC_TOP_TRACKS") . " (" . scalar @{$info->{tracks}} . ")",
			type => 'playlist',
			url => \&Plugins::GoogleMusic::TrackMenu::menu,
			itemActions => {
				items => {
					command     => ['googlemusicbrowse', 'items'],
					fixedParams => { mode => 'tracks', uri => $artist->{uri} },
				},
			},
			passthrough => [ $info->{tracks}, { all_access => 1, showArtist => 1, showAlbum => 1, playall => 1, playall_uri => $artist->{uri} } ],
		}, {
			name => cstring($client, "PLUGIN_GOOGLEMUSIC_RELATED_ARTISTS") . " (" . scalar @{$info->{related}} . ")",
			type => 'link',
			url => \&menu,
			itemActions => {
				allAvailableActionsDefined => 1,
				items => {
					command     => ['googlemusicbrowse', 'items'],
					fixedParams => { mode => 'artists', uri => $artist->{uri} },
				},
			},
			passthrough => [ $info->{related}, $opts ],
		} );
		$callback->({
			items => \@items,
			cover => $artist->{image},
			actions => {
				allAvailableActionsDefined => 1,
				items => {
					command     => ['googlemusicbrowse', 'items'],
					fixedParams => { mode => 'tracks', uri => $artist->{uri} },
				},
			},
		});
	} else {
		my ($tracks, $albums, $artists) = Plugins::GoogleMusic::Library::find_exact({artist => $artist->{name}});

		Plugins::GoogleMusic::AlbumMenu::menu($client, $callback, $args, $albums, $opts);
	}

	return;
}

1;
