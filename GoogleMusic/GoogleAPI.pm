package Plugins::GoogleMusic::GoogleAPI;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base 'Exporter';
use File::Spec::Functions;

our @EXPORT = qw($googleapi);
our $googleapi = get();

my $inlineDir;

BEGIN {
	$inlineDir = catdir(Slim::Utils::Prefs::preferences('server')->get('cachedir'), '_Inline');
	mkdir $inlineDir unless -d $inlineDir;
}

use Inline (Config => DIRECTORY => $inlineDir);
use Inline Python => <<'END_OF_PYTHON_CODE';

from gmusicapi import Mobileclient, Webclient, CallFailure
import hashlib

def get():
	class API(object):
		def __init__(self):
			self.api = Mobileclient()
			self.tracks = {}
			self.albums = {}
			self.artists = {}

		def login(self, username, password):
			return self.api.login(username, password)

		def logout(self):
			return self.api.logout()

		def get_all_songs(self):
			""" read all songs in user's library and store in local map """

			songs = self.api.get_all_songs()
			for track in songs:
				if 'albumArtRef' in track:
					track['albumArtUrl'] = track['albumArtRef'][0]['url']
				else:
					track['albumArtUrl'] = '/html/images/cover.png'
				uri = 'googlemusic:track:' + track['id']
				track['uri'] = uri
				self.tracks[uri] = track

		def is_authenticated(self):
			return self.api.is_authenticated()

		def get_stream_url(self, song_id, device_id):
			if self.api.is_authenticated():
				try:
					return self.api.get_stream_url(song_id, device_id)
				except CallFailure as error:
					pass

		def get_track(self, uri):
			if uri.startswith('googlemusic:all_access_track:'):
				store_track_id = uri[len('googlemusic:all_access_track:'):]
				track = self.api.get_track_info(store_track_id)
				if 'albumArtRef' in track:
					track['albumArtUrl'] = track['albumArtRef'][0]['url']
				else:
					track['albumArtUrl'] = '/html/images/cover.png'
				return track
			if uri in self.tracks:
				return self.tracks[uri]

		def get_track_by_id(self, song_id):
			return self.get_track('googlemusic:track:' + song_id)

		def search(self, query):
			if query is None:
				query = {}

			result = self.tracks.values()

			for (field, values) in query.iteritems():
				if not hasattr(values, '__iter__'):
					values = [values]
				for value in values:
					if type(value) is unicode:
						q = value.strip().lower()
					elif type(value) is str:
						q = value.decode('utf-8').strip().lower()
					elif type(value) is int:
						q = value

					track_filter = lambda t: q in t['title'].lower()
					album_filter = lambda t: q in t['album'].lower()
					artist_filter = lambda t: q in t['artist'].lower() or q in t['albumArtist'].lower()
					year_filter = lambda t: q == t.get('year')
					any_filter = lambda t: track_filter(t) or album_filter(t) or \
						artist_filter(t)

					if field == 'track':
						result = filter(track_filter, result)
					elif field == 'album':
						result = filter(album_filter, result)
					elif field == 'artist':
						result = filter(artist_filter, result)
					elif field == 'year':
						result = filter(year_filter, result)
					elif field == 'any':
						result = filter(any_filter, result)

			albums = {}
			artists = {}
			for track in result:
				album = self.track_to_album(track)
				artist = self.track_to_artist(track)
				albums[album['uri']] = album
				artists[artist['uri']] = artist

			albums = [album for (uri, album) in albums.items()]
			artists = [artist for (uri, artist) in artists.items()]

			return [result, albums, artists]

		def search_all_access(self, query, max_results=50):
			""" do a search in 'all access' and return found songs, albums and artists """

			results = self.api.search_all_access(query, max_results)
			albums = [album['album'] for album in results['album_hits']]
			artists = [artist['artist'] for artist in results['artist_hits']]
			songs = [track['track'] for track in results['song_hits']]

			for track in songs:
				track['uri'] = 'googlemusic:all_access_track:' + track['storeId']
				albumArtRef = track.get('albumArtRef')
				track['albumArtUrl'] = albumArtRef and albumArtRef[0]['url'] or '/html/images/cover.png'
			for album in albums:
				album['uri'] = 'googlemusic:album:' + album['albumId']
				album['albumArtUrl'] = album.get('albumArtRef', '/html/images/cover.png')

			# not sure if we should sort the albums here.. perhaps better to use google music's ranking..
			#albums = sorted(albums, key=lambda x: x.get('year'), reverse=True)

			for artist in artists:
				artist['uri'] = 'googlemusic:artist:' + artist['artistId']
				artist['artistImageBaseUrl'] = artist.get('artistArtRef', '/html/images/artists.png')
			return [songs, albums, artists]

		def get_artist_info(self, artist_id, max_top_tracks=5, max_rel_artist=5):
			""" return toptracks, albums, related_artists from the get_artist_info from the API """

			INCLUDE_ALBUMS = True
			results = self.api.get_artist_info(artist_id, INCLUDE_ALBUMS, max_top_tracks, max_rel_artist)
			toptracks = results.get('topTracks', [])
			albums = results.get('albums', [])
			# sort the albums on year
			albums = sorted(albums, key=lambda x: x.get('year'), reverse=True)
			related_artists = results.get('related_artists', [])

			# add URIs to albums:
			for album in albums:
				album['uri'] = 'googlemusic:album:' + album['albumId']
				album['albumArtUrl'] = album.get('albumArtRef', '/html/images/cover.png')
			for track in toptracks:
				track['uri'] = 'googlemusic:all_access_track:' + track['storeId']
				albumArtRef = track.get('albumArtRef')
				track['albumArtUrl'] = albumArtRef and albumArtRef[0]['url'] or '/html/images/cover.png'
			for artist in related_artists:
				artist['uri'] = 'googlemusic:artist:' + artist['artistId']
				artist['artistImageBaseUrl'] = artist.get('artistArtRef', '/html/images/artists.png')
			return toptracks, albums, related_artists

		def get_album_info(self, albumid, include_tracks=True):
			""" return API get_album_info """
			result = self.api.get_album_info(albumid, include_tracks)
			tracks = result.get('tracks', [])
			for track in tracks:
				track['uri'] = 'googlemusic:all_access_track:' + track['storeId']
				albumArtRef = track.get('albumArtRef')
				track['albumArtUrl'] = albumArtRef and albumArtRef[0]['url'] or '/html/images/cover.png'
			return result

		def get_all_playlist_contents(self):
			return self.api.get_all_playlist_contents()

		def track_to_artist(self, track):
			if 'myArtist' in track:
				return track['myArtist']
			artist = {}
			artist['name'] = track['artist']
			uri = 'googlemusic:artist:' + self.create_id(artist)
			artist['uri'] = uri
			if 'artistArtRef' in track:
				artist['artistImageBaseUrl'] = track['artistArtRef'][0]['url']
			else:
				artist['artistImageBaseUrl'] = '/html/images/artists.png'
			self.artists[uri] = artist
			track['myArtist'] = artist
			return artist

		def track_to_album(self, track):
			if 'myAlbum' in track:
				return track['myAlbum']
			album = {}
			artist = track['albumArtist']
			if artist.strip() == '':
				artist = track['artist']
			album['artist'] = artist
			album['name'] = track['album']
			album['year'] = track.get('year')  # year is not always present
			uri = 'googlemusic:album:' + self.create_id(album)
			album['uri'] = uri
			if 'albumArtRef' in track:
				album['albumArtUrl'] = track['albumArtRef'][0]['url']
			else:
				album['albumArtUrl'] = '/html/images/cover.png'
			self.albums[uri] = album
			track['myAlbum'] = album
			return album

		def create_id(self, d):
			return hashlib.md5(str(frozenset(d.items()))).hexdigest()

		def get_device_id(self, username, password):
			webapi = Webclient()
			webapi.login(username, password)
			devices = webapi.get_registered_devices()
			for device in devices:
				if device['type'] == 'PHONE':
					webapi.logout()
					# Omit the '0x' prefix
					return device['id'][2:]
			webapi.logout()

	return API()

END_OF_PYTHON_CODE

1;

__END__
