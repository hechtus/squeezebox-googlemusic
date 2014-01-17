package Plugins::GoogleMusic::TrackInfo;

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
		[ 'googlemusictrackinfo', 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ 'googlemusictrackinfo', 'playlist', '_method' ],
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

	$class->registerInfoProvider( addtrack => (
		menuMode  => 1,
		after     => 'top',
		func      => \&addTrackEnd,
	) );

	$class->registerInfoProvider( addtracknext => (
		menuMode  => 1,
		after     => 'addtrack',
		func      => \&addTrackNext,
	) );

	$class->registerInfoProvider( playitem => (
		menuMode  => 1,
		after     => 'addtracknext',
		func      => \&playTrack,
	) );

	$class->registerInfoProvider(
		artist => (
			after => 'top',
			func  => \&infoArtist,
		) );

	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( album => (
			after => 'top',
			func  => \&infoAlbum,
		) );

		$class->registerInfoProvider( year => (
			after => 'top',
			func  => \&infoYear,
		) );
	}

	$class->registerInfoProvider( duration => (
		after  => 'top',
		func   => \&infoDuration,
	) );

	$class->registerInfoProvider( title => (
		after  => 'top',
		func   => \&infoTitle,
	) );

	# TODO: Add track num, disc/disc number, genre, url, content type ...

}


sub menu {
	my ( $class, $client, $url, $track, $tags, $filter ) = @_;
	$tags ||= {};

	# If we don't have an ordering, generate one.
	# This will be triggered every time a change is made to the
	# registered information providers, but only then. After
	# that, we will have our ordering and only need to step
	# through it.
	my $infoOrdering = $class->getInfoOrdering;
	
	# $remoteMeta is an empty set right now. adding to allow for parallel construction with trackinfo
	my $remoteMeta = {};

	# Get track object if necessary
	if ( !$track ) {
		$track = Plugins::GoogleMusic::Library::get_track($url);
		if ( !$track ) {
			$log->error( "No track found for $url" );
			return;
		}
	}

	# Function to add menu items
	my $addItem = sub {
		my ( $ref, $items ) = @_;
		
		if ( defined $ref->{func} ) {
			
			my $item = eval { $ref->{func}->( $client, $url, $track, $remoteMeta, $tags, $filter ) };
			if ( $@ ) {
				$log->error( 'Track menu item "' . $ref->{name} . '" failed: ' . $@ );
				return;
			}
			
			return unless defined $item;
			
			# skip jive-only items for non-jive UIs
			return if $ref->{menuMode} && !$tags->{menuMode};
			
			# TBD: show artwork item to jive only if artwork exists
			return if $ref->{menuMode} && $tags->{menuMode} && $ref->{name} eq 'artwork' && !$track->coverArtExists;
			
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
				$log->error( 'TrackInfo menu item "' . $ref->{name} . '" failed: not an arrayref or hashref' );
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
		name  => $track->{title} || Slim::Music::Info::getCurrentTitle( $client, $url, 1 ),
		type  => 'opml',
		items => $items,
		cover => $track->{cover},
	};
}

sub infoArtist {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $artist = $track->{artist}->{name} ) {
		if ($track->{artist}->{uri} =~ 'unknown') {
			$item = {
				type  => 'text',
				label => 'ARTIST',
				name  => $artist,
			};
		} else {
			$item = {
				type  => 'link',
				url   => 'anyurl',
				label => 'ARTIST',
				name  => $artist,
				itemActions => {
					items => {
						command => ['googlemusicbrowse', 'items'],
						fixedParams => { uri => $track->{artist}->{uri} }
					},
				},
			};
		}
	}
	
	return $item;
}

sub infoAlbum {
	my ( $client, $url, $track ) = @_;
	
	my $item;

	if ( my $name = $track->{album}->{name} ) {
		$item = {
			type    => 'link',
			url     => 'anyurl',
			label => 'ALBUM',
			name  => $name,
			itemActions => {
				items => {
					command => ['googlemusicbrowse', 'items'],
					fixedParams => { uri => $track->{album}->{uri} }
				},
			},
		};
	}
	
	return $item;
}

sub infoYear {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $year = $track->{year} ) {
		$item = {
			type  => 'text',
			label => 'YEAR',
			name  => $year,
		};
	}
	
	return $item;
}

sub infoDuration {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $secs = $track->{secs} ) {
		my $duration = sprintf('%s:%02s', int($secs / 60), $secs % 60);
		$item = {
			type  => 'text',
			label => 'LENGTH',
			name  => $duration,
		};
	}
	
	return $item;
}

sub infoTitle {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $title = $track->{title} ) {
		$item = {
			type  => 'text',
			label => 'TITLE',
			name  => $title,
		};
	}
	
	return $item;
}

sub playTrack {
	my ( $client, $url, $track, $remoteMeta, $tags, $filter) = @_;

	return undef if !blessed($client);
	
	my $actions = {
		items => {
			command     => [ 'googlemusicplaylistcontrol' ],
			fixedParams => {cmd => 'load', uri => $track->{uri} },
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
	
sub addTrackEnd {
	my ( $client, $url, $track, $remoteMeta, $tags, $filter ) = @_;
	addTrack( $client, $url, $track, $remoteMeta, $tags, 'ADD_TO_END', 'add', $filter );
}

sub addTrackNext {
	my ( $client, $url, $track, $remoteMeta, $tags, $filter ) = @_;
	addTrack( $client, $url, $track, $remoteMeta, $tags, 'PLAY_NEXT', 'insert', $filter );
}

sub addTrack {
	my ( $client, $url, $track, $remoteMeta, $tags, $add_string, $cmd, $filter ) = @_;

	return undef if !blessed($client);

	my $actions = {
		items => {
			command     => [ 'googlemusicplaylistcontrol' ],
			fixedParams => {cmd => $cmd, uri => $track->{uri} },
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
		$feed = Plugins::GoogleMusic::TrackInfo->menu( $client, $uri, undef, $tags, \%filter );
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
	
	Slim::Control::XMLBrowser::cliQuery( 'googlemusictrackinfo', $feed, $request );
}

1;
