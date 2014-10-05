package Plugins::GoogleMusic::Recent;

use strict;
use warnings;

use Slim::Utils::Cache;
use Slim::Utils::Strings qw(cstring);

use Plugins::GoogleMusic::Plugin;
use Plugins::GoogleMusic::AlbumMenu;
use Plugins::GoogleMusic::ArtistMenu;

my $cache;

tie my %recentSearches, 'Tie::Cache::LRU', 50;
tie my %recentAlbums, 'Tie::Cache::LRU', 50;
tie my %recentArtists, 'Tie::Cache::LRU', 50;

sub init {
	$cache = shift;

	my $recent;

	# initialize recent items: need to add them to the LRU cache ordered by timestamp
	$recent = $cache->get('recentSearches');
	map {
		$recentSearches{$_} = $recent->{$_};
	} sort {
		$recent->{$a}->{ts} <=> $recent->{$b}->{ts}
	} keys %$recent;

	$recent = $cache->get('recentAlbums');
	map {
		$recentAlbums{$_} = $recent->{$_};
	} sort {
		$recent->{$a}->{ts} <=> $recent->{$b}->{ts}
	} keys %$recent;

	$recent = $cache->get('recentArtists');
	map {
		$recentArtists{$_} = $recent->{$_};
	} sort {
		$recent->{$a}->{ts} <=> $recent->{$b}->{ts}
	} keys %$recent;

	return;
}

sub recentSearchesAdd {
	my $search = shift;

	return unless $search;

	$recentSearches{$search} = {
		ts => time(),
	};

	$cache->set('recentSearches', \%recentSearches, 'never');

	return;
}

sub recentSearchesFeed {
	my ($client, $callback, $args, $opts) = @_;

	my @searches =
		sort { lc($a) cmp lc($b) }
		keys %recentSearches;

	my $search_func = $opts->{'all_access'} ?
		\&Plugins::GoogleMusic::Plugin::search_all_access :
		\&Plugins::GoogleMusic::Plugin::search;

	my $items = [];

	foreach (@searches) {
		push @$items, {
			type => 'link',
			name => $_,
			url  => $search_func,
			passthrough => [ $_ ],
		}
	}

	$items = [ {
		name => cstring($client, 'EMPTY'),
		type => 'text',
	} ] if !scalar @$items;

	$callback->({
		items => $items
	});

	return;
}

sub recentAlbumsAdd {
	my $album = shift;

	return unless $album;

	$recentAlbums{$album->{uri}} = {
		uri => $album->{uri},
		name => $album->{name},
		artist => $album->{artist},
		year => $album->{year},
		cover => $album->{cover},
		ts => time(),
	};

	$cache->set('recentAlbums', \%recentAlbums, 'never');

	return;
}

# Cache the menu because it may change when browsing into it. At least
# this works on a per client base.
my %recentAlbumsCache;
sub recentAlbumsFeed {
	my ($client, $callback, $args, $opts) = @_;

	my $clientId = $client ? $client->id() : '0';
	my $albums;

	if (defined $args->{'quantity'} && $args->{'quantity'} == 1 &&
		exists $recentAlbumsCache{$clientId}) {
		$albums = $recentAlbumsCache{$clientId};
	} else {
		# Access the LRU cache in reverse order to maintain the order
		@$albums = reverse
			grep { $opts->{all_access} ? $_->{uri} =~ '^googlemusic:album:B' : $_->{uri} !~ '^googlemusic:album:B' }
			map { $recentAlbums{$_} } reverse keys %recentAlbums;

		$recentAlbumsCache{$clientId} = $albums;
	}

	return Plugins::GoogleMusic::AlbumMenu::feed($client, $callback, $args, $albums, $opts);
}

sub recentArtistsAdd {
	my $artist = shift;

	return unless $artist;

	my $image = $artist->{image};

	if ($image =~ '^/html/images/' && $artist->{uri} =~ '^googlemusic:artist:A') {
		$image = Plugins::GoogleMusic::AllAccess::get_artist_image($artist->{uri});
	}

	$recentArtists{$artist->{uri}} = {
		uri => $artist->{uri},
		name => $artist->{name},
		image => $image,
		ts => time(),
	};

	$cache->set('recentArtists', \%recentArtists, 'never');

	return;
}

# Cache the menu because it may change when browsing into it. At least
# this works on a per client base.
my %recentArtistsCache;
sub recentArtistsFeed {
	my ($client, $callback, $args, $opts) = @_;

	my $clientId = $client ? $client->id() : '0';
	my $artists;

	if (defined $args->{'quantity'} && $args->{'quantity'} == 1 &&
		exists $recentArtistsCache{$clientId}) {
		$artists = $recentArtistsCache{$clientId};
	} else {
		# Access the LRU cache in reverse order to maintain the order
		@$artists = reverse
			grep { $opts->{all_access} ? $_->{uri} =~ '^googlemusic:artist:A' : $_->{uri} !~ '^googlemusic:artist:A' }
			map { $recentArtists{$_} } reverse keys %recentArtists;

		$recentArtistsCache{$clientId} = $artists;
	}

	return Plugins::GoogleMusic::ArtistMenu::feed($client, $callback, $args, $artists, $opts);
}


1;
