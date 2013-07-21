package Plugins::GoogleMusic::GoogleAPI;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Inline (Config => DIRECTORY => '/var/lib/squeezeboxserver/_Inline/',);
use Inline Python => <<'END';

from gmusicapi import Webclient

def get():
	return Webclient()

END

1;

__END__
