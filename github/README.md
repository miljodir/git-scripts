Scripts in this folder are used for various purposes. Most relate to automatically sending emails.
The emails use Send-Mailmessage over port 25, and should not be run outside Equinor's intranet. Most ISP's will block port 25 anyways.

Most of the scripts require an admin level PAT token in order to function. The admin token should be removed once the script is used, or stored in a safe place, as it has a lot of power.

Most of the scripts are semi-automatic. The semi-automatic scripts typically have an excel sheet as input. This can be improved if you so like, but in our case the scripts with only semi-automation were one-off things (e.g. find all users not authenticated to the Github org with SSO and send notifiying emails to them)

Routinely scripts, e.g. finding outside collaborators and their access to repos are somewhat more automated.