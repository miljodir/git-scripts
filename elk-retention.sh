#!/usr/bin/env bash
# Uses the Elasticsearh API to close and delete Indices
# Must be run on the ES host
# Does not perform action on 'indices older than', but on 'indices created in the month 
# n-months ago'
ELK_ENDPOINT="localhost:9200/"
ELK_INDICES="filebeat-"
ELK_CLOSE_TIME_MONTHS="2"
ELK_DELETE_TIME_MONTHS="6"
CURLARGS="--fail --silent --show-error"

# Close INDICES
# Create date filter with: (todays-date) - (n-months) format YYYY.MM
CLOSE_DATE=$(date -d "-${ELK_CLOSE_TIME_MONTHS} month" +%Y.%m.)
echo -e "Closing indices using this filter:\n${ELK_ENDPOINT}${ELK_INDICES}${CLOSE_DATE}*"
# Performs flush on indices first to stop any open transactions...best practise
curl $CURLARGS -XPOST "${ELK_ENDPOINT}${ELK_INDICES}${CLOSE_DATE}*/_flush"
# Closed indices can later be opened with '/_open'
curl $CURLARGS -XPOST "${ELK_ENDPOINT}${ELK_INDICES}${CLOSE_DATE}*/_close"

# Delete INDICES
DELETE_DATE=$(date -d "-${ELK_DELETE_TIME_MONTHS} month" +%Y.%m.)
echo ""
echo -e "Deleting indices using this filter:\n${ELK_ENDPOINT}${ELK_INDICES}${DELETE_DATE}*"
curl $CURLARGS -XDELETE "${ELK_ENDPOINT}${ELK_INDICES}${CLOSE_DATE}*"
