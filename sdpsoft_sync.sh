#!/usr/bin/env bash
#===============================================================================
#
#          FILE:  sync.sh
#
#         USAGE:  sync.sh [-a, --all] [-f, --files] [--only-env-files]"
#
#   DESCRIPTION:  Uses rsync to push and syncronize local sdpsoft directory
#                 to all remote RGS Statoil servers.
#
#       OPTIONS:  -a --all -f --files --only-env-files
#  REQUIREMENTS:  run as spdadm on vmm03.prod.sdp.ststoil.no in /data/sdpsoft
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:  Stig O. M. Ofstad, stoo@statoil.com
#       COMPANY:  Statoil
#       VERSION:  1.0
#       CREATED:  ti. 13. mars 12:32:27 +0100 2018
#      REVISION:  ---
#===============================================================================
PROGRAMNAME=$(basename $0)
cd $(dirname $0)
SDPSOFT_REMOTE_DIR="/prog/sdpsoft/"
SERVERS=(
    tr-vsdp02.tr.statoil.no
    st-vcris01.st.statoil.no
    be-linrgsn002.be.statoil.no
    hou-linrgsn034.hou.statoil.no
    rio-linrgsn003.rio.statoil.no
    cal-linrgsn009.cal.statoil.no
    stjohn-linrgs006.stjohn.statoil.no
    ha-linrgsn050.ha.statoil.no
    st-lcmtop01.st.statoil.no
    hou-lcctop01.hou.statoil.no
    ffs01.hou.statoil.no
)

# Print usage info if none or an invalid argument is given.
function usage {
    echo "usage: $PROGRAMNAME [-a, --all] [-f, --files] [--only-env-files]"
    echo -e "      -f, --files           Only sync these files. Example: \"./$PROGRAMNAME --files python2.7.14 tmux-*\""
    echo "      -a, --all             Sync all files"
    echo "      --only-env-files      Only sync the 'env.sh' and 'env.csh' files"
}

if [ "$1" = "--only-env-files" ]; then
    if [ ! -f "env.sh" ] || [ ! -f "env.csh" ]; then
        echo "Error: One or more of the 'env-files' can not be found...exiting"
        exit 1
    fi
    for server in ${SERVERS[@]}; do
        echo "----------------------------------------------"
        echo " SYNCING to $server"
        rsync -va --include="env.sh" --include="env.csh" --exclude="*" . $server:$SDPSOFT_REMOTE_DIR
    done
elif [ "$1" = "-a" ] || [ "$1" = "--all" ]; then
    for server in ${SERVERS[@]}; do
        echo "----------------------------------------------"
        echo " SYNCING to $server"
        # Sync the updated environment-files last to avoid putting the updated
        # software in limbo while the new version is syncing
        rsync -va --delete --exclude-from=".gitignore" --exclude="env.sh" --exclude="env.csh" . $server:$SDPSOFT_REMOTE_DIR
        rsync -va --delete --include="env.sh" --include="env.csh" --exclude="*" . $server:$SDPSOFT_REMOTE_DIR
    done
elif [ "$1" = "-f" ] || [ "$1" = "--files" ]; then
    # Shift the $@ parameters. $2 becomes $1. To omit '--files'.
    shift 1
    for server in ${SERVERS[@]}; do
        echo "----------------------------------------------"
        echo " SYNCING to $server"
        for file in "$@"; do
            rsync -va --delete --exclude-from=".gitignore" $file $server:$SDPSOFT_REMOTE_DIR
        done
    done
else
    echo "Error: Requires atleast one argument."
    usage
    exit 1
fi
exit 0
