#!/usr/bin/env bash

HOST="$1"
PORT="$2"
WARNING_DAYS="$3"
CRITICAL_DAYS="$4"

output=$(echo | openssl s_client -connect $HOST:$PORT -servername $HOST 2>/dev/null | \
         sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' | \
         openssl x509 -noout -subject -dates 2>/dev/null)

valid_from_date=$(echo $output | sed 's/.*notBefore=\(.*\).*not.*/\1/g')
valid_until_date=$(echo $output | sed 's/.*notAfter=\(.*\)$/\1/g')



epoch_now=$(date +%s -d 'now')
epoch_valid_from=$(date +%s -d "$valid_from_date")
epoch_valid_until=$(date +%s -d "$valid_until_date")

seconds_before_valid=$(expr $epoch_valid_from - $epoch_now)
days_before_valid=$(expr $seconds_before_valid / 86400)

seconds_until_expiry=$(expr $epoch_valid_until - $epoch_now)
days_until_expiry=$(expr $seconds_until_expiry / 86400)

if [[ $days_before_valid -gt 0 ]]; then
    echo "Certificate for $HOST is not valid until $days_before_valid days"
    exit 1
elif [[ $days_until_expiry -lt $CRITICAL_DAYS ]]; then
    echo "Certificate for $HOST expires in $days_until_expiry days!"
    exit 2
elif [[ $days_until_expiry -lt $WARNING_DAYS ]]; then
    echo "Certificate for $HOST expires in $days_until_expiry days!"
    exit 1
else
    echo "Certificate for $HOST expires in $days_until_expiry days, good time ^___^"
    exit 0
fi
