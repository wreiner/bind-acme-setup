#!/usr/bin/env python3
# Source: https://stackoverflow.com/q/54637332

import argparse
import json
import dns.update
import dns.query
import dns.tsigkeyring
import dns.resolver
from dns.tsig import HMAC_SHA512
import sys


class DnsUpdate():
    def __init__(self):
        self.parse_commandline_arguments()
        self.read_config(self.args.get("config"))

    def parse_commandline_arguments(self):
        parser = argparse.ArgumentParser()

        parser._action_groups.pop()
        required = parser.add_argument_group('required arguments')
        optional = parser.add_argument_group('optional arguments')

        required.add_argument("-z", "--zone",
            nargs=1, help="Zone to update", required=True)
        required.add_argument("-c", "--challenge",
            nargs=1, help="Challenge to set", required=True)

        optional.add_argument("-C", "--config",
            nargs='?',
            help="Location of config file",
            default="/etc/update-txt-records.json"),

        # convert args to dict
        self.args = vars(parser.parse_args())

    def read_config(self, configfile):
        try:
            with open(configfile, "r") as jsonfile:
                self.config = json.load(jsonfile)
        except FileNotFoundError as fnferror:
            print("Error in parsing config file {}".format(fnferror))
            sys.exit(1)
        except PermissionError as permerror:
            print("Error in parsing config file {}".format(permerror))
            sys.exit(1)

    def validate_config_entry(self, zone):
        try:
            if {"secret", "keyname", "dnsserver"} <= set(self.config[zone]):
                return True
        except KeyError:
            return False

        return False

    def update_record(self):
        """
        Adds an _acme-chllenge.domain.tld TXT record.

        The updated record is supposed to have its own zone therefore the
        recordfqdn and the update zone is the same.
        """
        try:
            zone = self.args.get("zone")[0]
        except Exception as err:
            print("Error parsing command line argument for zone - {}".format(err))
            sys.exit(1)

        if not self.validate_config_entry(zone):
            print("Error validating configuration entry for zone {}"
                " - set values for secret, keyname and dnsserver.".format(zone))
            sys.exit(1)

        recordfqdn = "_acme-challenge.{}.".format(zone)
        dnsserver = self.config[zone]["dnsserver"]
        secret = self.config[zone]["secret"]
        keyname = self.config[zone]["keyname"]
        challenge = self.args.get("challenge")[0]

        keyring = dns.tsigkeyring.from_text({keyname: secret})

        update = dns.update.Update(recordfqdn,
            keyring=keyring,
            keyalgorithm=HMAC_SHA512)
        update.add(recordfqdn, 300, 'TXT', challenge)

        print("updating record ..")
        try:
            dns.query.tcp(update, dnsserver)
        except Exception as err:
            print("Error updating record for zone {} - {}".format(zone, err))
            sys.exit(1)

if __name__ == '__main__':
    dnsu = DnsUpdate()
    dnsu.update_record()
    print("done.")
