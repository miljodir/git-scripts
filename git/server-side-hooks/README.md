# Server Side Hooks

A server side git hook is a script that can be run when something is being comitted.\n
[Gits documentation on hooks](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)\n
[GitLabs documentation on hook creation](https://docs.gitlab.com/ce/administration/custom_hooks.html)

## Usage

Scripts placed in this folder should have the name in form of `$hookType_$whatItDoes`, like for instance `pre-receive_print_friendly_message_on_commit`
When using these scripts, place them were you need and rename them accordingly.
