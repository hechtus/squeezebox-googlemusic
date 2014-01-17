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
		[ 1, 1, 1, \&cliPlaylistCmd ]
	);
}

sub name {
	# It seems that this has to be a unique name.
	return __PACKAGE__;
}

my $emptyItemList = [{ignore => 1}];

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
	my ( $class, $client, $url, $track, $tags ) = @_;
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
			
			# skip jive-only items for non-jive UIs
			return if $ref->{menuMode} && !$tags->{menuMode};
			
			# TBD: show artwork item to jive only if artwork exists
			return if $ref->{menuMode} && $tags->{menuMode} && $ref->{name} eq 'artwork' && !$track->coverArtExists;
			
			my $item = eval { $ref->{func}->( $client, $url, $track, $remoteMeta, $tags ) };
			if ( $@ ) {
				$log->error( 'Track menu item "' . $ref->{name} . '" failed: ' . $@ );
				return;
			}
			
			return unless defined $item;
			
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
		name  => $track->{title},
		type  => 'opml',
		items => $items,
		play  => $track->{uri},
		cover => $track->{cover},
		menuComplete => 1,
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
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;
	my $items = [];
	my $jive;
	
	return $items if !blessed($client);
	
	my $play_string = cstring($client, 'PLAY');

	my $actions;

	# "Play Song" in current playlist context is 'jump'
	if ( $tags->{menuContext} eq 'playlist' ) {
		
		# do not add item if this is current track and already playing
		return $emptyItemList if $tags->{playlistIndex} == Slim::Player::Source::playingSongIndex($client)
					&& $client->isPlaying();
		
		$actions = {
			go => {
				player => 0,
				cmd => [ 'playlist', 'jump', $tags->{playlistIndex} ],
				nextWindow => 'parent',
			},
		};
		# play, add and add-hold all have the same behavior for this item
		$actions->{play} = $actions->{go};
		$actions->{add} = $actions->{go};
		$actions->{'add-hold'} = $actions->{go};

	# typical "Play Song" item
	} else {

		$actions = {
			go => {
				player => 0,
				cmd => [ 'googlemusicplaylistcontrol' ],
				params => {
					cmd => 'load',
					uri => $track->{uri},
				},
				nextWindow => 'nowPlaying',
			},
		};
		# play is go
		$actions->{play} = $actions->{go};
	}

	$jive->{actions} = $actions;
	$jive->{style} = 'itemplay';

	push @{$items}, {
		type => 'text',
		name => $play_string,
		jive => $jive, 
	};
	
	return $items;
}

sub addTrackNext {
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;
	my $string = cstring($client, 'PLAY_NEXT');
	my $cmd = $tags->{menuContext} eq 'playlist' ? 'playlistnext' : 'insert';
	
	return addTrack( $client, $url, $track, $remoteMeta, $tags, $string, $cmd );
}

sub addTrackEnd {
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;

	my ($string, $cmd);

	# "Add Song" in current playlist context is 'delete'
	if ( $tags->{menuContext} eq 'playlist' ) {
		$string = cstring($client, 'REMOVE_FROM_PLAYLIST');
		$cmd    = 'delete';
	} else {
		$string = cstring($client, 'ADD_TO_END');
		$cmd    = 'add';
	}
	
	return addTrack( $client, $url, $track, $remoteMeta, $tags, $string, $cmd );
}

sub addTrack {
	my ( $client, $url, $track, $remoteMeta, $tags , $string, $cmd ) = @_;

	my $items = [];
	my $jive;

	return $items if !blessed($client);
	
	my $actions;
	# remove from playlist
	if ( $cmd eq 'delete' ) {
		
		# Do not add this item if only one item in playlist
		return $emptyItemList if Slim::Player::Playlist::count($client) < 2;

		$actions = {
			go => {
				player     => 0,
				cmd        => [ 'playlist', 'delete', $tags->{playlistIndex} ],
				nextWindow => 'parent',
			},
		};
		# play, add and add-hold all have the same behavior for this item
		$actions->{play} = $actions->{go};
		$actions->{add} = $actions->{go};
		$actions->{'add-hold'} = $actions->{go};

	# play next in the playlist context
	} elsif ( $cmd eq 'playlistnext' ) {
		
		# Do not add this item if only one item in playlist
		return $emptyItemList if Slim::Player::Playlist::count($client) < 2;

		my $moveTo = Slim::Player::Source::playingSongIndex($client) || 0;
		
		# do not add item if this is current track or already the next track
		return $emptyItemList if $tags->{playlistIndex} == $moveTo || $tags->{playlistIndex} == $moveTo+1;
		
		if ( $tags->{playlistIndex} > $moveTo ) {
			$moveTo = $moveTo + 1;
		}
		$actions = {
			go => {
				player     => 0,
				cmd        => [ 'playlist', 'move', $tags->{playlistIndex}, $moveTo ],
				nextWindow => 'parent',
			},
		};
		# play, add and add-hold all have the same behavior for this item
		$actions->{play} = $actions->{go};
		$actions->{add} = $actions->{go};
		$actions->{'add-hold'} = $actions->{go};


	# typical "Add Song" item
	} else {

		$actions = {
			add => {
				player => 0,
				cmd => [ 'googlemusicplaylistcontrol' ],
				params => {
					cmd => $cmd,
					uri => $track->{uri},
				},
				nextWindow => 'parent',
			},
		};
		# play and go have same behavior as go here
		$actions->{play} = $actions->{add};
		$actions->{go} = $actions->{add};
	}

	$jive->{actions} = $actions;

	push @{$items}, {
		type => 'text',
		name => $string,
		jive => $jive, 
	};
	
	return $items;
}

my $cachedFeed;

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
	
	my $tags = {
		menuMode      => $menuMode,
		menuContext   => $menuContext,
		playlistIndex => $playlist_index,
	};
	
	my $feed;
	
	# Default menu
	if ( $uri ) {
		$feed = Plugins::GoogleMusic::TrackInfo->menu( $client, $uri, undef, $tags );
	} else {
		$log->error("Didn't get a valid track uri.");
		$request->setStatusBadParams();
		return;
	}

	$cachedFeed = $feed if $feed;
	
	Slim::Control::XMLBrowser::cliQuery( 'googlemusictrackinfo', $feed, $request );
}

sub cliPlaylistCmd {
	my $request = shift;
	
	my $client  = $request->client;
	my $method  = $request->getParam('_method');

	unless ($client && $method && $cachedFeed) {
		$request->setStatusBadParams();
		return;
	}
	
	return 	Slim::Control::XMLBrowser::cliQuery( 'googlemusictrackinfo', $cachedFeed, $request );
}

1;
