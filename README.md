squeezebox-googlemusic
======================

This is a [Squeezebox](http://www.mysqueezebox.com/) (Logitech Media
Server) Plug-in for playing music from your [Google Play
Music](https://play.google.com/music/) library. It is based on the
Python [Unofficial Google Play Music
API](http://unofficial-google-music-api.readthedocs.org/) and the
ability of inlining Python in Perl programs.

Installation
------------

1. You will need a Google account and some music and/or playlists in
your library.

2. Install Python and the [Unofficial Google Play Music
API](https://github.com/simon-weber/Unofficial-Google-Music-API>). You
will have to use the **current development branch**.

3. Install the Perl [Inline](http://search.cpan.org/~ingy/Inline/)
package and [Inline::Python](http://search.cpan.org/~nine/Inline-Python/).

4. Create the directory `/var/lib/squeezeboxserver/_Inline/` with the
same credentials as the other directories in
`/var/lib/squeezeboxserver/`. This directory is used by Inline to
build the Python code.

5. Copy the Google Music plug-in to the plug-in folder of the
squeezebox. Under Linux this would be
`/var/lib/squeezeboxserver/Plugins/`. For development reasons you may
also create a symbolic link to your source code. Finally you should
have `/var/lib/squeezeboxserver/Plugins/GoogleMusic`.

Usage
-----

1. Go to the plug-in settings page and set your Google username and
password for the Google Music plug-in.

2. Restart the squeezebox. Someday, this will be handled automatically
by the plug-in.

Project resources
-----------------

* [Source code](https://github.com/hechtus/squeezebox-googlemusic)
* [Issue tracker](https://github.com/hechtus/squeezebox-googlemusic/issues)
* [Current development snapshot](https://github.com/hechtus/squeezebox-googlemusic/archive/master.zip)

ToDo
----

* There are still lots of things to do. This project just
  started. Feel free to
  [contribute](https://help.github.com/articles/fork-a-repo) to help
  for the first release.
