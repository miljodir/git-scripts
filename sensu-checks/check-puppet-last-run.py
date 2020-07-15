#! /usr/bin/env python3
import argparse
import datetime

parser = argparse.ArgumentParser(description='Check Puppet status')
parser.add_argument('--summary-file', dest='puppet_status',
                    default="/opt/puppetlabs/puppet/cache/state/last_run_summary.yaml",
                    help=f"path to the puppet last_run_summary.yaml file. Defaults to '/opt/puppetlabs/puppet/cache/state/last_run_summary.yaml'")

parser.add_argument('--warn-age', dest='warn_age', type=int, default=3600,
                    help="Exits with '2'(warning) if last run older then this value(seconds). Defaults to 3600")

parser.add_argument('--crit-age', dest='crit_age', type=int, default=7200,
                    help="Exits with '1'(critical) if last run older then this value(seconds). Defaults to 7200")

args = parser.parse_args()
status = {}
last_run = 0
last_run_age = 0
message = ""


def pretty_seconds(seconds: int):
    days = seconds // (24 * 3600)
    seconds = seconds % (24 * 3600)
    hours = seconds // 3600
    seconds = seconds % 3600
    minutes = seconds // 60
    if days:
        return f"{days}d:{hours}h:{minutes}m"
    else:
        return f"{hours}h:{minutes}m"


# All this to avoid none-standardlib dependencies.  Like PyYaml
with open(args.puppet_status, "r") as stream:
    for line in stream.readlines():
        if not line[0] == " ":
            continue
        stripped = line.strip()
        key, value = stripped.split(": ", 1)
        status[key] = value

if status.get("last_run"):
    last_run = int(status["last_run"])
    last_run_age = int(datetime.datetime.now().timestamp()) - last_run
    message = f"Puppet last run {pretty_seconds(last_run_age)} ago"
else:
    print(f"Missing information about the last run timestamp")
    exit(1)

if last_run_age > args.warn_age:
    print(message)
    exit(2)
elif last_run_age > args.crit_age:
    print(message)
    exit(1)
else:
    print(message)
    exit(0)
