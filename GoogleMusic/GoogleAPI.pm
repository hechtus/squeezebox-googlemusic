package Plugins::GoogleMusic::GoogleAPI;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base 'Exporter';

our @EXPORT = qw($googleapi);
our $googleapi = get();

use Inline (Config => DIRECTORY => '/var/lib/squeezeboxserver/_Inline/',);
use Inline Python => <<'END_OF_PYTHON_CODE';

from gmusicapi import Mobileclient, CallFailure
import hashlib

def get():
    class API(object):
        def __init__(self):
            self.api = Mobileclient()
            self.tracks = {}
            self.albums = {}
            self.artists = {}

        def login(self, username, password):
            if not self.api.login(username, password):
                return False
            songs = self.api.get_all_songs()
            for track in songs:
                track['albumArtUrl'] = track['albumArtRef'][0]['url']
                uri = 'googlemusic:track:' + track['id']
                track['uri'] = uri
                self.tracks[uri] = track
            return True

        def logout(self):
            return self.api.logout()

        def is_authenticated(self):
            return self.api.is_authenticated()

        def get_stream_url(self, song_id, device_id):
            if self.api.is_authenticated():
                try:
                    return self.api.get_stream_url(song_id, device_id)
                except CallFailure as error:
                    pass

        def get_track(self, uri):
            return self.tracks[uri]

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
                    date_filter = lambda t: q in t['year']
                    any_filter = lambda t: track_filter(t) or album_filter(t) or \
                        artist_filter(t)
        
                    if field == 'track':
                        result = filter(track_filter, result)
                    elif field == 'album':
                        result = filter(album_filter, result)
                    elif field == 'artist':
                        result = filter(artist_filter, result)
                    elif field == 'date':
                        result = filter(date_filter, result)
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
                artist['artistImageBaseUrl'] = ''
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
            album['year'] = track['year']
            uri = 'googlemusic:album:' + self.create_id(album)
            album['uri'] = uri
            album['albumArtUrl'] = track['albumArtRef'][0]['url']
            self.albums[uri] = album
            track['myAlbum'] = album
            return album

        def create_id(self, d):
            return hashlib.md5(str(frozenset(d.items()))).hexdigest()

    return API()

END_OF_PYTHON_CODE

1;

__END__
