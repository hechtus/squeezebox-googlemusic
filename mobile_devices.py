#!/usr/bin/env python

import argparse
from gmusicapi import Webclient

def main():
    parser = argparse.ArgumentParser(description = 'List all devices registered for Google Play Music')

    parser.add_argument('username', help = 'Your Google Play Music username')
    parser.add_argument('password', help = 'Your very secret password')

    args = parser.parse_args()
    
    api = Webclient(validate = False)

    if not api.login(args.username, args.password):
        print "Could not login to Google Play Music. Incorrect username or password."
        return

    for device in api.get_registered_devices():
        print '%s | %s | %s | %s' % (device['name'],
                                     device.get('manufacturer'),
                                     device['type'],
                                     device['id'])

    api.logout()

if __name__ == '__main__':
    main()
