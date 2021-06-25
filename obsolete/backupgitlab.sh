#!/usr/bin/env bash

echo "Doing db dump"
docker exec "sql01.prd.git.statoil.no" pg_dump -U gitlab --no-owner --no-acl gitlab > /data/docker/dockerfiles/gitlab/gitlab.sql
#STATUS=$?
#if [ "$STATUS" != "0" ]; then
#  echo $STATUS > /data/docker/dockerfiles/gitlab/backup_status
#  exit 2
#fi
#echo "Syncing db dump"
#rsync -va -e ssh /data/docker/dockerfiles/gitlab/gitlab.sql root@tr-vsdp02.tr.statoil.no:/data/backup/gitlab/gitlab.sql
#STATUS=$?
#if [ "$STATUS" != "0" ]; then
#  echo $STATUS > /data/docker/dockerfiles/gitlab/backup_status
#  exit 2
#fi
#echo "Syncing gitlab files"
#rsync -va -e ssh /data/docker/dockerfiles/gitlab/data/gitlab/ root@tr-vsdp02.tr.statoil.no:/data/backup/gitlab
#STATUS=$?
#if [ "$STATUS" != "0" ]; then
#  echo $STATUS > /data/docker/dockerfiles/gitlab/backup_status
#  exit 2
#fi
#echo $STATUS > /data/docker/dockerfiles/gitlab/backup_status
