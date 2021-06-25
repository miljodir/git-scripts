import requests
import csv

# From Github API Doc;
# To add a membership between an organization member and a team, the authenticated user must be an organization owner or a maintainer of the team.
#
# Need admin:org scope
token = ''
github_url = 'https://api.github.com'
organization = 'equinor'
team_id = '28951'
headers = {'Accept': 'application/json',
           'Authorization': 'Bearer ' + token}


reader = csv.DictReader(open('developers.csv'))
github_usernames = []
for line in reader:
    github_usernames.append(line['gituser'])


for user in github_usernames:
    # Defaults to the "member" role
    url = f'{github_url}/teams/{team_id}/memberships/{user}'
    response = requests.put(url=url, headers=headers)
