package Plugins::GoogleMusic::GoogleAPI;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Inline (Config => DIRECTORY => '/var/lib/squeezeboxserver/_Inline/',);
use Inline Python => <<'END';

from gmusicapi import Webclient

class GoogleAPI(object):

    def __init__(self):
        self.api = Webclient()

    def login(self, username, password):
        self.api.login(username, password)
        self.songs = self.api.get_all_songs()

    def logout(self):
        self.api.logout()

    def get_stream_url(self, song_id):
        return self.api.get_stream_urls(song_id)[0]

    def search(self, query):
        if query is None:
            query = {}
        
        result = self.songs
        
        for (field, values) in query.iteritems():
            if not hasattr(values, '__iter__'):
                values = [values]
            for value in values:
                q = value.strip().lower()

                track_filter = lambda t: q in t['titleNorm']
                album_filter = lambda t: q in t['albumNorm']
                artist_filter = lambda t: q in t['artistNorm'] or q in t['albumArtistNorm']
                date_filter = lambda t: q in str(t['year'])
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
                
        return result

def get():
    return GoogleAPI()

END

1;

__END__
