#!/usr/bin/env bash
# Script meant to be run as a sensu check. Returns status of last backup job 
LOG_PATH="/tmp/"
LOG_PREFIX="backup_report_"
TIMESTAMP=$(date +\%y.\%m.\%d_) 
BACKUP_LOG="$LOG_PATH$LOG_PREFIX$TIMESTAMP*.log"
# This is perhaps not the best way to do it. An alternative could be to
# Integrate a solution like this in the backup-script
#       if [ $? -ne 0 ]
#       then
#       echo "ERROR:"
#       fi

# In case there are several logs from same day, get the last one.
BACKUP_LOG="$(ls $BACKUP_LOG | cut -d " " -f 1 | tail -n 1)"
if [ ! -f "$BACKUP_LOG" ]; then
    echo "Could not find the file $BACKUP_LOG. Assuming the backup went OK. "
    exit 0 
fi
# If the logfile containes "error", echo the error line with context, and exit with code 2
if grep -i --quiet "error" $BACKUP_LOG; then
    echo "The backup job completet with error(s)! Error with context:"
    grep -i --color=auto --max-count 1 --before-context=2 --after-context=1 "error" $BACKUP_LOG
    exit 2
# Same as above, just with "warning" and exit code 1
elif grep -i --quiet "warning" $BACKUP_LOG; then
    echo "The backup job completet with warning(s)! Warning with context:"
    grep -i --before-context=1 --max-count 1 --after-context=1 "warning" $BACKUP_LOG
    exit 1
else
    echo "Could not locate the keywords 'warning' or 'error' in the last backup report. Status OK."
    exit 0
fi

