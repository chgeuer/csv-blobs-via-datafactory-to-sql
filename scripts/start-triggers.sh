#!/bin/bash

# https://learn.microsoft.com/en-us/rest/api/datafactory/triggers/start?tabs=HTTP

# curl \
#    --silent \
#    --url https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 \
#    --location \
#    --output ./jq
#
# chmod +x ./jq
# sudo mv ./jq /usr/local/bin
# sudo chown root.root /usr/local/bin/jq


echo "TRIGGERJOINCHAR: ${TRIGGERJOINCHAR}"
echo "TRIGGERS: ${TRIGGERS}"
echo "DATAFACTORY_ID: ${DATAFACTORY_ID}"

managementPortal="https://management.azure.com"

access_token="$(curl --silent --get --header "Metadata: true" \
    --data-urlencode "api-version=2018-02-01" \
    --data-urlencode "resource=${managementPortal}" \
    --url "http://169.254.169.254/metadata/identity/oauth2/token" \
    | jq -r ".access_token")"

IFS="${TRIGGERJOINCHAR}" read -a triggerNames <<< "${TRIGGERS}"

for triggerName in "${triggerNames[@]}"
do
  # https://learn.microsoft.com/en-us/rest/api/datafactory/triggers/start?tabs=HTTP

  curl \
    --include \
    --request POST \
    --url "${managementPortal}${DATAFACTORY_ID}/triggers/${triggerName}/start?api-version=2018-06-01" \
    --header "Authorization: Bearer ${access_token}" \
    --header "Content-Length: 0"

done
