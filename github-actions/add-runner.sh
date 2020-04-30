#!/lbin/bash

source .env-github

WORKDIR=/data/github-runners
OS=centos
OSMAJOR=8
OSMINOR=1
OSFAMILY=$OS$OSMAJOR.x
OSFULLNAME=$OS$OSMAJOR.$OSMINOR
TARGETDIR=$WORKDIR/equinor-shared-centos$OSVERSION-runner$RUNNERID

mkdir $TARGETDIR &&  tar -C $TARGETDIR -xvf $WORKDIR/actions-runner-linux-x64-*.tar.gz

$TARGETDIR/config.sh --url https://github.com/equinor --name equinor-shared-$OSFAMILY-runner$RUNNERID --labels $OS,$OSFAMILY,$OSFULLNAME,shared,on-prem --unattended --token $TOKEN

cd $TARGETDIR && sudo $TARGETDIR/svc.sh install && sudo $TARGETDIR/svc.sh start