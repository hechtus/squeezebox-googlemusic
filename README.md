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
   Note: you need a subsciption to All Access if you want to use those
   features
2. Install Python and the [Unofficial Google Play Music
   API](https://github.com/simon-weber/Unofficial-Google-Music-API>) by
   running:

         sudo pip install gmusicapi
         
         NOTE! For the 'All Access' functionality you need the latest version
         of the gmusicapi (which supports get_album_info):

         sudo easy_install https://github.com/simon-weber/Unofficial-Google-Music-API/archive/develop.zip

3. Install the Perl CPAN [Inline](http://search.cpan.org/~ingy/Inline/)
   package and
   [Inline::Python](http://search.cpan.org/~nine/Inline-Python/) by
   running:

         sudo cpan App::cpanminus
         sudo cpanm Inline
         sudo cpanm Inline::Python

4. To install the plugin, add this repository URL
   http://hechtus.github.io/squeezebox-googlemusic/repository/repo.xml
   to your squeezebox plugin settings page.

Usage
-----

1. Go to the plug-in settings page and set your Google username and
   password for the Google Music plug-in.

2. The mobile device ID is a 16-digit hexadecimal string (without the
   '0x' prefix) identifying the Android device you must already have
   registered for Google Play Music. You can obtain this ID by dialing
   `*#*#8255#*#*` on your phone (see the aid) or using this
   [App](https://play.google.com/store/apps/details?id=com.evozi.deviceid)
   (see the Google Service Framework ID Key). You may also use the
   script `mobile_devices.py` to list all registered devices. If your
   Android device is already registered, you should leave the field
   `Mobile Device ID` empty. It will be filled in automatically after
   setting the username and password.

3. You will find the plug-in in the 'My Apps' section of the
   squeezebox menu.
 
Project resources
-----------------

* [Source code](https://github.com/hechtus/squeezebox-googlemusic)
* [Issue tracker](https://github.com/hechtus/squeezebox-googlemusic/issues)
* [Current development snapshot](https://github.com/hechtus/squeezebox-googlemusic/archive/master.zip)

ToDo
----

There are still lots of things to do. This project just
started. Feel free to
[contribute](https://help.github.com/articles/fork-a-repo) or to
[report
bugs](https://github.com/hechtus/squeezebox-googlemusic/issues) to
help for the first release. Here are some open issues you may help on:

* Recent searches
* Artist menu
* Catch all Google API exceptions and errors
* Improve Track and Album Info
