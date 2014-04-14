squeezebox-googlemusic
======================

[![Travis CI build status](https://travis-ci.org/hechtus/squeezebox-googlemusic.png?branch=master)](https://travis-ci.org/hechtus/squeezebox-googlemusic)

This is a [Squeezebox](http://www.mysqueezebox.com/) (Logitech Media
Server) Plug-in for playing music from your [Google Play
Music](https://play.google.com/music/) library and All Access. It is
based on the Python [Unofficial Google Play Music
API](http://unofficial-google-music-api.readthedocs.org/) and the
ability of inlining Python in Perl programs.

Installation
------------

This installation procedure will only work on Linux based systems. At
the moment I do not know if this will ever work on Windows or Mac
OS. Please let me know if you found a way to get this plugin running
on non-Linux systems to extend this How-to.

1. You will need a Google account and some music and/or playlists in
   your library. If you want to use Google Music All Access features
   you will need a subscription to this service.

1. Install Python and [Python pip](http://www.pip-installer.org).

1. Install the [Unofficial Google Play Music
   API](https://github.com/simon-weber/Unofficial-Google-Music-API>)
   by running:

         sudo pip install gmusicapi
         
   **Note**: You will need at least version 3.1.1 of gmusicapi.

1. To be able to build the Perl package Inline::Python (see below) you
   will need the Python developer package. The name of the package and
   the way how to install it depends on your Linux distribution. On
   **Debian** based systems you will have to do:

         sudo apt-get install python-dev

   On **redhat** systems do:

         sudo yum install python-devel

1. Install the Perl CPAN package
   [Inline](http://search.cpan.org/~ingy/Inline/) and
   [Inline::Python](http://search.cpan.org/~nine/Inline-Python/) by
   running:

         sudo cpan App::cpanminus
         sudo cpanm --notest Inline
         sudo cpanm --notest Inline::Python

1. To install the plugin, add the repository URL
   http://hechtus.github.io/squeezebox-googlemusic/repository/repo.xml
   to your squeezebox plugin settings page.

Usage
-----

1. Go to the plug-in settings page and set your Google username and
   password for the Google Music plug-in. You can also use an
   application-specific password also known as 2-Step Verification
   which is desribed in detail on this [support
   page](https://support.google.com/accounts/answer/185833).

1. The mobile device ID is a 16-digit hexadecimal string (without a
   '0x' prefix) identifying an Android device or a string of the form
   `ios:01234567-0123-0123-0123-0123456789AB` (including the `ios:`
   prefix) identifying an iOS device you must already have registered
   for Google Play Music. On Android you can obtain this ID by dialing
   `*#*#8255#*#*` on your phone (see the aid) or using this
   [App](https://play.google.com/store/apps/details?id=com.evozi.deviceid)
   (see the Google Service Framework ID Key). You may also use the
   script `mobile_devices.py` to list all registered devices. If your
   Android or iOS device is already registered, you may leave the
   field `Mobile Device ID` empty. It will be filled in automatically
   after setting the username and password.

   **Note**: A registered PC MAC address will not work as a mobile
     device ID.

1. Enable All Access if you have an All Access subscription.

1. You will find the plug-in in the 'My Apps' section of the
   squeezebox menu.

Donate for this	Plugin
----------------------

If you are enjoying this plugin feel free to donate for it.

<form action="https://www.paypal.com/cgi-bin/webscr" method="post" target="_top">
<input type="hidden" name="cmd" value="_s-xclick">
<input type="hidden" name="hosted_button_id" value="Z2KE8W5HW9F8W">
<input type="image" src="https://www.paypalobjects.com/de_DE/DE/i/btn/btn_donateCC_LG.gif" border="0" name="submit" alt="Jetzt einfach, schnell und sicher online bezahlen – mit PayPal.">
<img alt="" border="0" src="https://www.paypalobjects.com/de_DE/i/scr/pixel.gif" width="1" height="1">
</form>
 
Project resources
-----------------

* [Source code](https://github.com/hechtus/squeezebox-googlemusic)
* [Issue tracker](https://github.com/hechtus/squeezebox-googlemusic/issues)
* [Current development snapshot](https://github.com/hechtus/squeezebox-googlemusic/archive/master.zip)

ToDo
----

I'm looking forward to your help. Feel free to
[contribute](https://help.github.com/articles/fork-a-repo) or to
[report
bugs](https://github.com/hechtus/squeezebox-googlemusic/issues). Here
are some things you may help on:

* Get this plugin running on non-Linux systems
* Add or improve
  [translations](https://github.com/hechtus/squeezebox-googlemusic/blob/master/GoogleMusic/strings.txt)
  to other languages
* Test the plugin with various Android or iOS Apps. Is it working with
  iPeng?
* Support for creating and deleting radio stations
* Improve Track and Album Info
