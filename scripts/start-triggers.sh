#!/bin/bash

echo "TRIGGERJOINCHAR: ${TRIGGERJOINCHAR}"
echo "TRIGGERS: ${TRIGGERS}"
echo "DATAFACTORY_ID: ${DATAFACTORY_ID}"

managementPortal="https://management.azure.com"

access_token="$(curl --silent --get --header "Metadata: true" \
    --data-urlencode "api-version=2018-02-01" \
    --data-urlencode "resource=${managementPortal}" \
    --url "http://169.254.169.254/metadata/identity/oauth2/token" \
    | jq -r ".access_token")"

# string.split("|", "a|b|c")
IFS="${TRIGGERJOINCHAR}" read -a triggerNames <<< "${TRIGGERS}"

for triggerName in "${triggerNames[@]}"
do
  # https://learn.microsoft.com/en-us/rest/api/datafactory/triggers/start?tabs=HTTP

  error="BadRequest"
  while [ "${error}" == "BadRequest" ]
  do
    response="$( curl \
      --silent \
      --request POST \
      --url "${managementPortal}${DATAFACTORY_ID}/triggers/${triggerName}/start?api-version=2018-06-01" \
      --header "Authorization: Bearer ${access_token}" \
      --header "Content-Length: 0" )"

    error="$( echo "${response}" | jq -r '.error.code' )"

    if [ "${error}" == "BadRequest" ]; then
      echo "Problem starting the trigger: ${response}"
      sleep 5
    fi
  done
done
