package Plugins::GoogleMusic::AlbumInfo;

use strict;
use warnings;
use base qw(Slim::Menu::Base);

use Data::Dumper;

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Prefs;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');


sub init {
	my $class = shift;
	$class->SUPER::init();

	Slim::Control::Request::addDispatch(
		[ 'googlemusicalbuminfo', 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ 'googlemusicalbuminfo', 'playlist', '_method' ],
		[ 1, 1, 1, \&cliQuery ]
	);
}

sub name {
	# It seems that this has to be a unique name.
	return __PACKAGE__;
}

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;
	
	$class->SUPER::registerDefaultInfoProviders();

	$class->registerInfoProvider( addalbum => (
		menuMode  => 1,
		after     => 'top',
		func      => \&addAlbumEnd,
	) );

	$class->registerInfoProvider( addalbumnext => (
		menuMode  => 1,
		after     => 'addalbum',
		func      => \&addAlbumNext,
	) );

	$class->registerInfoProvider( playitem => (
		menuMode  => 1,
		after     => 'addalbumnext',
		func      => \&playAlbum,
	) );

	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( artist => (
			after => 'top',
			func  => \&infoArtist,
		) );
	}
	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( album => (
			after => 'top',
			func  => \&infoAlbum,
		) );
	}
	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( year => (
			after => 'top',
			func  => \&infoYear,
		) );
	}

}


sub menu {
	my ( $class, $client, $url, $album, $tags, $filter ) = @_;
	$tags ||= {};

	# If we don't have an ordering, generate one.
	# This will be triggered every time a change is made to the
	# registered information providers, but only then. After
	# that, we will have our ordering and only need to step
	# through it.
	my $infoOrdering = $class->getInfoOrdering;
	
	# $remoteMeta is an empty set right now. adding to allow for parallel construction with trackinfo
	my $remoteMeta = {};

	# Get album object if necessary
	if ( !$album ) {
		$album = Plugins::GoogleMusic::Library::get_album($url);
		if ( !$album ) {
			$log->error( "No album found for $url" );
			return;
		}
	}

	# Function to add menu items
	my $addItem = sub {
		my ( $ref, $items ) = @_;
		
		if ( defined $ref->{func} ) {
			
			my $item = eval { $ref->{func}->( $client, $url, $album, $remoteMeta, $tags, $filter ) };
			if ( $@ ) {
				$log->error( 'Album menu item "' . $ref->{name} . '" failed: ' . $@ );
				return;
			}
			
			return unless defined $item;
			
			# skip jive-only items for non-jive UIs
			return if $ref->{menuMode} && !$tags->{menuMode};
			
			# TBD: show artwork item to jive only if artwork exists
			return if $ref->{menuMode} && $tags->{menuMode} && $ref->{name} eq 'artwork' && !$album->coverArtExists;
			
			if ( ref $item eq 'ARRAY' ) {
				if ( scalar @{$item} ) {
					push @{$items}, @{$item};
				}
			}
			elsif ( ref $item eq 'HASH' ) {
				return if $ref->{menuMode} && !$tags->{menuMode};
				if ( scalar keys %{$item} ) {
					push @{$items}, $item;
				}
			}
			else {
				$log->error( 'AlbumInfo menu item "' . $ref->{name} . '" failed: not an arrayref or hashref' );
			}				
		}
	};
	
	# Now run the order, which generates all the items we need
	my $items = [];
	
	for my $ref ( @{ $infoOrdering } ) {
		# Skip items with a defined parent, they are handled
		# as children below
		next if $ref->{parent};
		
		# Add the item
		$addItem->( $ref, $items );
		
		# Look for children of this item
		my @children = grep {
			$_->{parent} && $_->{parent} eq $ref->{name}
		} @{ $infoOrdering };
		
		if ( @children ) {
			my $subitems = $items->[-1]->{items} = [];
			
			for my $child ( @children ) {
				$addItem->( $child, $subitems );
			}
		}
	}
	
	return {
		name  => $album->{name} || Slim::Music::Info::getCurrentTitle( $client, $url, 1 ),
		type  => 'opml',
		items => $items,
		cover => $album->{cover},
	};
}

sub infoArtist {
	my ( $client, $url, $album ) = @_;
	
	my $item;
	
	if ( my $artist = $album->{artist}->{name} ) {
		$item = {
			type  => 'text',
			label => 'ARTIST',
			name  => $artist,
			itemActions => {
				items => {
					command => ['googlemusicbrowse', 'items'],
					fixedParams => { uri => $album->{artist}->{uri} }
				},
			}
		};
	}
	
	return $item;
}

sub infoAlbum {
	my ( $client, $url, $album ) = @_;
	
	my $item;
	
	if ( my $name = $album->{name} ) {
		$item = {
			type  => 'text',
			label => 'ALBUM',
			name  => $name,
		};
	}
	
	return $item;
}

sub infoYear {
	my ( $client, $url, $album ) = @_;
	
	my $item;
	
	if ( my $year = $album->{year} ) {
		$item = {
			type  => 'text',
			label => 'YEAR',
			name  => $year,
		};
	}
	
	return $item;
}

sub playAlbum {
	my ( $client, $url, $album, $remoteMeta, $tags, $filter) = @_;

	return undef if !blessed($client);
	
	my $actions = {
		items => {
			command     => [ 'googlemusicplaylistcontrol' ],
			fixedParams => {cmd => 'load', uri => $album->{uri} },
		},
	};
	$actions->{'play'} = $actions->{'items'};
	
	return {
		itemActions => $actions,
		nextWindow  => 'nowPlaying',
		type        => 'text',
		playcontrol => 'play',
		name        => cstring($client, 'PLAY'),
		jive        => {style => 'itemplay'},
	};
}
	
sub addAlbumEnd {
	my ( $client, $url, $album, $remoteMeta, $tags, $filter ) = @_;
	addAlbum( $client, $url, $album, $remoteMeta, $tags, 'ADD_TO_END', 'add', $filter );
}

sub addAlbumNext {
	my ( $client, $url, $album, $remoteMeta, $tags, $filter ) = @_;
	addAlbum( $client, $url, $album, $remoteMeta, $tags, 'PLAY_NEXT', 'insert', $filter );
}

sub addAlbum {
	my ( $client, $url, $album, $remoteMeta, $tags, $add_string, $cmd, $filter ) = @_;

	return undef if !blessed($client);

	my $actions = {
		items => {
			command     => [ 'googlemusicplaylistcontrol' ],
			fixedParams => {cmd => $cmd, uri => $album->{uri} },
		},
	};
	$actions->{'play'} = $actions->{'items'};
	$actions->{'add'}  = $actions->{'items'};
	
	return {
		itemActions => $actions,
		nextWindow  => 'parent',
		type        => 'text',
		playcontrol => $cmd,
		name        => cstring($client, $add_string),
	};
}


# keep a very small cache of feeds to allow browsing into a artist info feed
# we will be called again without $url or $albumId when browsing into the feed
tie my %cachedFeed, 'Tie::Cache::LRU', 2;

sub cliQuery {
	my $request = shift;

	# WebUI or newWindow param from SP side results in no
	# _index _quantity args being sent, but XML Browser actually needs them, so they need to be hacked in
	# here and the tagged params mistakenly put in _index and _quantity need to be re-added
	# to the $request params
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');
	if ( $index =~ /:/ ) {
		$request->addParam(split (/:/, $index));
		$index = 0;
		$request->addParam('_index', $index);
	}
	if ( $quantity =~ /:/ ) {
		$request->addParam(split(/:/, $quantity));
		$quantity = 200;
		$request->addParam('_quantity', $quantity);
	}
	
	my $client         = $request->client;
	my $uri            = $request->getParam('uri');
	my $menuMode       = $request->getParam('menu') || 0;
	my $menuContext    = $request->getParam('context') || 'normal';
	my $playlist_index = defined( $request->getParam('playlist_index') ) ?  $request->getParam('playlist_index') : undef;
	my $connectionId   = $request->connectionID;
	
	my %filter;
	foreach (qw(artist_id genre_id year)) {
		if (my $arg = $request->getParam($_)) {
			$filter{$_} = $arg;
		}
	}	

	my $tags = {
		menuMode      => $menuMode,
		menuContext   => $menuContext,
		playlistIndex => $playlist_index,
	};
	
	my $feed;
	
	# Default menu
	if ( $uri ) {
		$feed = Plugins::GoogleMusic::AlbumInfo->menu( $client, $uri, undef, $tags, \%filter );
	}
	elsif ( $cachedFeed{ $connectionId } ) {
		$feed = $cachedFeed{ $connectionId };
	}
	else {
		$request->setStatusBadParams();
		return;
	}

	# TBD: This doesn't work with the webclient
	# $cachedFeed{ $connectionId } = $feed if $feed;
	
	Slim::Control::XMLBrowser::cliQuery( 'googlemusicalbuminfo', $feed, $request );
}

1;
