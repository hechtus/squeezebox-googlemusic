package Plugins::GoogleMusic::Plugin;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;
use base qw(Slim::Plugin::OPMLBased);
use Scalar::Util qw(blessed);
use Encode qw(decode_utf8);
use MIME::Base64;

use vars qw($VERSION);

use Slim::Control::Request;
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Strings qw(string cstring);
use Slim::Menu::GlobalSearch;

use Plugins::GoogleMusic::Settings;
use Plugins::GoogleMusic::GoogleAPI;
use Plugins::GoogleMusic::ProtocolHandler;
use Plugins::GoogleMusic::Image;
use Plugins::GoogleMusic::Library;
use Plugins::GoogleMusic::AllAccess;
use Plugins::GoogleMusic::Playlists;
use Plugins::GoogleMusic::Radio;
use Plugins::GoogleMusic::Recent;
use Plugins::GoogleMusic::TrackMenu;
use Plugins::GoogleMusic::AlbumMenu;
use Plugins::GoogleMusic::ArtistMenu;

my $log;
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();
my $cache = Slim::Utils::Cache->new('googlemusic', 4);

BEGIN {
	$log = Slim::Utils::Log->addLogCategory({
		'category'     => 'plugin.googlemusic',
		'defaultLevel' => 'WARN',
		'description'  => 'PLUGIN_GOOGLEMUSIC',
	});
}

sub getDisplayName {
	return 'PLUGIN_GOOGLEMUSIC';
}

sub initPlugin {
	my $class = shift;

	# Set the version of this plugin
	$VERSION = $class->_pluginDataFor('version');

	# Chech version of gmusicapi first
	if (!blessed($googleapi) || (Plugins::GoogleMusic::GoogleAPI::get_version() lt '4.0.0')) {
		$class->SUPER::initPlugin(
			tag    => 'googlemusic',
			feed   => \&badVersion,
			is_app => 1,
			weight => 1,
			);
		return;
	}

	$class->SUPER::initPlugin(
		tag    => 'googlemusic',
		feed   => \&toplevel,
		is_app => 1,
		weight => 1,
	);

	if (main::WEBUI) {
		Plugins::GoogleMusic::Settings->new;
	}

	# Initialize submodules
	Plugins::GoogleMusic::AllAccess::init($cache);
	Plugins::GoogleMusic::Image::init();
	Plugins::GoogleMusic::Radio::init();
	Plugins::GoogleMusic::Recent::init($cache);

	# Try to login. If SSL verification fails, login() raises an
	# exception. Catch it to allow the plugin to be started.
	eval {
		$googleapi->login($prefs->get('username'),
						  decode_base64($prefs->get('password')));
	};
	if ($@) {
		$log->error("Not able to login to Google Play Music: $@");
	}

	# Refresh My Library and Playlists
	if (!$googleapi->is_authenticated()) {
		$log->error(string('PLUGIN_GOOGLEMUSIC_NOT_LOGGED_IN'));
	} else {
		Plugins::GoogleMusic::Library::refresh();
		Plugins::GoogleMusic::Playlists::refresh();
	}

	Slim::Menu::TrackInfo->registerInfoProvider( googlemusicRating => (
		isa => 'top',
		func  => \&ratingMenu,
	) );

	Slim::Menu::TrackInfo->registerInfoProvider( googlemusicStartRadio => (
		after => 'middle',
		func  => \&startRadioMenu,
	) );

	Slim::Menu::TrackInfo->registerInfoProvider( googlemusic => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );

	Slim::Menu::GlobalSearch->registerInfoProvider( googlemusic => (
		after => 'middle',
		func  => \&searchInfoMenu,
	) );

	# Register this Plugin for smart mixes provided by the SmartMix
	# plugin. Check if the SmartMix plugin is enabled and properly
	# installed.
	if ( Slim::Utils::PluginManager->isEnabled('Plugins::SmartMix::Plugin') ) {
		eval {
			require Plugins::SmartMix::Services;
		};

		if (!$@) {
			main::INFOLOG && $log->info("SmartMix plugin is available - let's use it!");

			# Smart mixes are supported for My Music and All Access
			# separately. The user is able to enable/disable both
			# features independently.
			require Plugins::GoogleMusic::SmartMixMyMusic;
			require Plugins::GoogleMusic::SmartMixAllAccess;

			# Provide a version number to both modules. This is
			# required for SmartMix services.
			Plugins::GoogleMusic::SmartMixMyMusic->init($VERSION);
			Plugins::GoogleMusic::SmartMixAllAccess->init($VERSION);

			# Register both modules separately.
			Plugins::SmartMix::Services->registerHandler('Plugins::GoogleMusic::SmartMixMyMusic', 'GoogleMusicMyMusic');
			Plugins::SmartMix::Services->registerHandler('Plugins::GoogleMusic::SmartMixAllAccess', 'GoogleMusicAllAccess');
		}
	}

	return;
}

sub shutdownPlugin {
	if (blessed($googleapi)) {
		$googleapi->logout();
	}

	return;
}


sub badVersion {
	my ($client, $callback, $args) = @_;

	my @menu;
	push @menu, {
		name => cstring($client, 'PLUGIN_GOOGLEMUSIC_BAD_VERSION'),
		type => 'text',
		wrap => 1,
	};

	$callback->(\@menu);

	return;
}

sub toplevel {
	my ($client, $callback, $args) = @_;

	my @menu;

	if ($prefs->get('all_access_enabled')) {
		@menu = (
			{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_MY_MUSIC'), type => 'link', url => \&my_music },
			{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_ALL_ACCESS'), type => 'link', url => \&all_access },
		);
		$callback->(\@menu);
	} else {
		# go to my_music directly, making it the top level menu
		my_music($client, $callback, $args);
	}

	return;
}

sub my_music {
	my ($client, $callback, $args) = @_;
	my @menu = (
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_BROWSE'), type => 'link', url => \&search },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_LAST_ADDED'), type => 'playlist', url => \&lastAdded },
		{ name => cstring($client, 'PLAYLISTS'), type => 'link', url => \&Plugins::GoogleMusic::Playlists::feed },
		{ name => cstring($client, 'SEARCH'), type => 'search', url => \&search },
		{ name => cstring($client, 'RECENT_SEARCHES'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentSearchesFeed, passthrough => [ { "all_access" => 0 } ] },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RECENT_ALBUMS'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentAlbumsFeed, passthrough => [ { "all_access" => 0 } ] },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RECENT_ARTISTS'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentArtistsFeed, passthrough => [ { "all_access" => 0 } ] },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RELOAD_LIBRARY'), type => 'func', url => \&reload_library },
	);

	$callback->(\@menu);

	return;
}

sub lastAdded {
	my ($client, $callback, $args) = @_;

	# Get all tracks from the library
	my $tracks = Plugins::GoogleMusic::Library::searchTracks();

	# Show them sorted by the creation timestamp
	return Plugins::GoogleMusic::TrackMenu::feed($client, $callback, $args, $tracks,
												 { showArtist => 1, showAlbum => 1, sortByCreation => 1, playall => 1 });
}

sub reload_library {
	my ($client, $callback, $args) = @_;

	Plugins::GoogleMusic::Library::refresh();
	Plugins::GoogleMusic::Playlists::refresh();

	my @menu;
	push @menu, {
		'name' => cstring($client, 'PLUGIN_GOOGLEMUSIC_LIBRARY_RELOADED'),
		'type' => 'text',
	};

	$callback->(\@menu);

	return;
}

sub all_access {
	my ($client, $callback, $args) = @_;
	my @menu = (
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_IFL_RADIO'), type => 'audio', url => "googlemusicradio:station:IFL" },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_MY_RADIO_STATIONS'), type => 'link', url => \&Plugins::GoogleMusic::Radio::menu },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RADIO_GENRES'), type => 'link', url => \&Plugins::GoogleMusic::Radio::genresFeed },
		{ name => cstring($client, 'SEARCH'), type => 'search', url => \&search_all_access },
		{ name => cstring($client, 'RECENT_SEARCHES'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentSearchesFeed, passthrough => [ { "all_access" => 1 } ] },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RECENT_ALBUMS'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentAlbumsFeed, passthrough => [ { "all_access" => 1 } ] },
		{ name => cstring($client, 'PLUGIN_GOOGLEMUSIC_RECENT_ARTISTS'), type => 'link', url => \&Plugins::GoogleMusic::Recent::recentArtistsFeed, passthrough => [ { "all_access" => 1 } ] },
	);

	$callback->(\@menu);

	return;
}

sub search {
	my ($client, $callback, $args, $search) = @_;

	$args->{search} ||= $search;

	# The search string may be empty. We could forbid this.
	$args->{search} ||= '';
	my @query = split(' ', $args->{search});

	Plugins::GoogleMusic::Recent::recentSearchesAdd($args->{search}) if scalar @query;

	my ($tracks, $albums, $artists) = Plugins::GoogleMusic::Library::search({'any' => \@query});

	my @menu = (
		{ name => cstring($client, "ARTISTS") . " (" . scalar @$artists . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::ArtistMenu::feed,
		  passthrough => [ $artists, { sortArtists => 1, sortAlbums => 1 } ] },
		{ name => cstring($client, "ALBUMS") . " (" . scalar @$albums . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::AlbumMenu::feed,
		  passthrough => [ $albums, { sortAlbums => 1 } ] },
		{ name => cstring($client, "SONGS") . " (" . scalar @$tracks . ")",
		  type => 'playlist',
		  url => \&Plugins::GoogleMusic::TrackMenu::feed,
		  passthrough => [ $tracks, { showArtist => 1, showAlbum => 1, sortTracks => 1 } ], },
	);

	$callback->(\@menu);

	return;
}

sub search_all_access {
	my ($client, $callback, $args, $search, $opts) = @_;

	$args->{search} ||= $search;

	# The search string may be empty. We could forbid this.
	$args->{search} ||= '';

	my $result = Plugins::GoogleMusic::AllAccess::search($args->{search});

	if (!$result) {
		$callback->(errorMenu($client));
		return;
	}

	# Pass to artist/album/track menu when doing artist/album/track search
	if ($opts->{artistSearch}) {
		return Plugins::GoogleMusic::ArtistMenu::feed($client, $callback, $args, $result->{artists},
													  { all_access => 1 });
	}
	if ($opts->{albumSearch}) {
		return Plugins::GoogleMusic::AlbumMenu::feed($client, $callback, $args, $result->{albums},
													 { all_access => 1 });
	}
	if ($opts->{trackSearch}) {
		return Plugins::GoogleMusic::TrackMenu::feed($client, $callback, $args, $result->{tracks},
													 { all_access => 1, showArtist => 1, showAlbum => 1 });
	}

	# Do not add to recent searches when we are doing artist/album/track search
	Plugins::GoogleMusic::Recent::recentSearchesAdd($args->{search}) if $args->{search};

	my @menu = (
		{ name => cstring($client, "ARTISTS") . " (" . scalar @{$result->{artists}} . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::ArtistMenu::feed,
		  passthrough => [ $result->{artists}, { all_access => 1 } ], },
		{ name => cstring($client, "ALBUMS") . " (" . scalar @{$result->{albums}} . ")",
		  type => 'link',
		  url => \&Plugins::GoogleMusic::AlbumMenu::feed,
		  passthrough => [ $result->{albums}, { all_access => 1 } ], },
		{ name => cstring($client, "SONGS") . " (" . scalar @{$result->{tracks}} . ")",
		  type => 'playlist',
		  url => \&Plugins::GoogleMusic::TrackMenu::feed,
		  passthrough => [ $result->{tracks}, { all_access => 1, showArtist => 1, showAlbum => 1 } ], },
	);

	$callback->(\@menu);

	return;
}

sub trackInfoMenu {
	my ($client, $url, $track, $remoteMeta) = @_;
	
	return unless $client;
	return unless $prefs->get('all_access_enabled');

	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;

	my @menu;
	my $item;

	if ($artist) {
		push @menu, {
			name        => cstring($client, 'ARTIST') . ": " . $artist,
			url         => \&search_all_access,
			passthrough => [ $artist, { artistSearch => 1 } ],
			type        => 'link',
			favorites   => 0,
		},
	};

	if ($album) {
		push @menu, {
			name        => cstring($client, 'ALBUM') . ": " . $album,
			url         => \&search_all_access,
			passthrough => [ $album, { albumSearch => 1 } ],
			type        => 'link',
			favorites   => 0,
		},
	};

	if ($title) {
		push @menu, {
			name        => cstring($client, 'TRACK') . ": " . $title,
			url         => \&search_all_access,
			passthrough => [ $artist ? "$artist $title" : $title, { trackSearch => 1 } ],
			type        => 'playlist',
			favorites   => 0,
		},
	};

	if (scalar @menu) {
		$item = {
			name  => cstring($client, 'PLUGIN_GOOGLEMUSIC_ON_GOOGLEMUSIC'),
			items => \@menu,
		};
	}

	return $item;
}

# Trackinfo Rating Menu for Like/Dislike
sub ratingMenu {
	my ($client, $url, $track, $remoteMeta) = @_;
	
	return unless $client;

	return unless $url =~ '^googlemusic:track:';

	# Get the rating for the track. Should be fast as it comes from our cache.
	my $rating = Plugins::GoogleMusic::Library::get_track($url)->{rating};

	# Create two menu entries: Like/Unlike and Dislike/Don't dislike
	my $items = [{
		name => cstring($client, ($rating >= 4) ? 'PLUGIN_GOOGLEMUSIC_UNLIKE' : 'PLUGIN_GOOGLEMUSIC_LIKE'),
		type => 'link',
		url => \&like,
		passthrough => [ $url, ($rating >= 4) ? 0 : 5 ],
		nextWindow => 'parent',
		forceRefresh => 1,
		favorites => 0,
	},{
		name => cstring($client, ($rating != 0 && $rating < 3) ? "PLUGIN_GOOGLEMUSIC_DONT_DISLIKE" : "PLUGIN_GOOGLEMUSIC_DISLIKE"),
		type => 'link',
		url => \&dislike,
		passthrough => [ $url, ($rating != 0 && $rating < 3) ? 0 : 1 ],
		nextWindow => 'parent',
		forceRefresh => 1,
		favorites => 0,
	}];

	return $items;
}

sub like {
	my ($client, $callback, $args, $url, $rating) = @_;

	Plugins::GoogleMusic::Library::changeRating($url, $rating);

	$callback->({
		items => [{
			type => 'text',
			name => cstring($client, $rating ? 'PLUGIN_GOOGLEMUSIC_LIKE' : 'PLUGIN_GOOGLEMUSIC_UNLIKE'),
			showBriefly => 1,
			popback => 2
		}]
	}) if $callback;

	return;
}

sub dislike {
	my ($client, $callback, $args, $url, $rating) = @_;

	Plugins::GoogleMusic::Library::changeRating($url, $rating);

	$callback->({
		items => [{
			type => 'text',
			name => cstring($client, $rating ? 'PLUGIN_GOOGLEMUSIC_DISLIKE' : 'PLUGIN_GOOGLEMUSIC_DONT_DISLIKE'),
			showBriefly => 1,
			popback => 2
		}]
	}) if $callback;

	return;
}

# Trackinfo start radio menu
sub startRadioMenu {
	my ($client, $url, $track, $remoteMeta) = @_;
	
	return unless $client;

	return unless $url =~ '^googlemusic:track:';

	return unless $prefs->get('all_access_enabled');

	# Get the optional storeId for the track from the library
	my $storeId;
	if ($url !~ '^googlemusic:track:T') {
		$storeId = Plugins::GoogleMusic::Library::get_track($url)->{storeId};
	}

	my $items = [{
		name  => cstring($client, "PLUGIN_GOOGLEMUSIC_START_RADIO"),
		url => \&Plugins::GoogleMusic::Radio::startRadioFeed,
		passthrough => [ $storeId ? 'googlemusic:track:' .  $storeId : $url ],
		nextWindow => 'nowPlaying',
	}];

	return $items;
}

sub searchInfoMenu {
	my ($client, $tags) = @_;

	# For some reason the search string gets encoded
	my $search = decode_utf8($tags->{search});

	# Always search in my music
	my @items = ({
		name        => cstring($client, 'PLUGIN_GOOGLEMUSIC_MY_MUSIC'),
		url         => \&search,
		passthrough => [ $search ],
	});

	# All Access is optional
	if ($prefs->get('all_access_enabled')) {
		push @items, {
			name        => cstring($client, 'PLUGIN_GOOGLEMUSIC_ALL_ACCESS'),
			url         => \&search_all_access,
			passthrough => [ $search ],
		};
	}

	return {
		name => cstring($client, 'PLUGIN_GOOGLEMUSIC'),
		items => \@items,
	};
}

sub errorMenu {
	my ($client) = @_;

	return [{
		name => cstring($client, 'PLUGIN_GOOGLEMUSIC_ERROR'),
		type => 'text',
	}];

}

1;
