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


echo "TRIGGERS: ${TRIGGERS}"
echo "DATAFACTORY_ID: ${DATAFACTORY_ID}"


# https://learn.microsoft.com/en-us/rest/api/datafactory/triggers/start?tabs=HTTP

resource="https://management.azure.com/"

access_token="$(curl --silent --get --header "Metadata: true" \
    --data-urlencode "api-version=2018-02-01" \
    --data-urlencode "resource=${resource}" \
    --url "http://169.254.169.254/metadata/identity/oauth2/token" \
    | jq -r ".access_token")"

curl \
    --include \
    --request POST \
    --url "https://management.azure.com/${DATAFACTORY_ID}/triggers/exampleTrigger/start" \
    --data-urlencode "api-version=2018-06-01" \
    --header "Authorization: Bearer ${access_token}"
