package Plugins::GoogleMusic::ArtistMenu;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Plugins::GoogleMusic::Plugin;
use Plugins::GoogleMusic::TrackMenu;
use Plugins::GoogleMusic::AlbumMenu;


my $log = logger('plugin.googlemusic');


sub feed {
	my ($client, $callback, $args, $artists, $opts) = @_;

	return $callback->(menu($client, $args, $artists, $opts));
}

sub menu {
	my ($client, $args, $artists, $opts) = @_;

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

	return {
		items => \@items,
	};
}

sub _showArtist {
	my ($client, $artist, $opts) = @_;

	my $item = {
		name => $artist->{name},
		image => $artist->{image},
		type => 'link',
		url => \&_artistMenu,
		passthrough => [ $artist, $opts ],
	};

	# If the artists are sorted by name add a text key to easily jump
	# to artists on squeezeboxes
	if ($opts->{sortArtists}) {
		$item->{textkey} = substr($artist->{name}, 0, 1);
	}

	return $item;
}


sub _artistMenu {
	my ($client, $callback, $args, $artist, $opts) = @_;

	if ($opts->{all_access}) {
		my $info = Plugins::GoogleMusic::AllAccess::get_artist_info($artist->{uri});

		if (!$info) {
			$callback->(Plugins::GoogleMusic::Plugin::errorMenu($client));
			return;
		}

		my @menu = (
			{ name => cstring($client, "ALBUMS") . " (" . scalar @{$info->{albums}} . ")",
			  type => 'link',
			  url => \&Plugins::GoogleMusic::AlbumMenu::feed,
			  passthrough => [ $info->{albums}, { all_access => 1, sortAlbums => 1 } ] },
			{ name => cstring($client, "PLUGIN_GOOGLEMUSIC_TOP_TRACKS") . " (" . scalar @{$info->{tracks}} . ")",
			  type => 'playlist',
			  url => \&Plugins::GoogleMusic::TrackMenu::feed,
			  passthrough => [ $info->{tracks}, { all_access => 1, showArtist => 1, showAlbum => 1, playall => 1 } ] },
			{ name => cstring($client, "PLUGIN_GOOGLEMUSIC_RELATED_ARTISTS") . " (" . scalar @{$info->{related}} . ")",
			  type => 'link',
			  url => \&feed,
			  passthrough => [ $info->{related}, $opts ] },
		);

		if (exists $info->{artistBio}) {
			push @menu, {
				name => cstring($client, "PLUGIN_GOOGLEMUSIC_BIOGRAPHY"),
				type => 'link',
				items => [ { name => $info->{artistBio}, type => 'text', wrap => 1 } ],
			}
		}
		
		push @menu, {
			name => cstring($client, "PLUGIN_GOOGLEMUSIC_START_RADIO"),
			url => \&Plugins::GoogleMusic::Radio::startRadioFeed,
			passthrough => [ $artist->{uri} ],
			cover => $artist->{image},
			nextWindow => 'nowPlaying',
		};

		$callback->(\@menu);
	} else {
		my ($tracks, $albums, $artists) = Plugins::GoogleMusic::Library::find_exact({artist => $artist->{name}});

		Plugins::GoogleMusic::AlbumMenu::feed($client, $callback, $args, $albums, $opts);
	}

	return;
}

1;
