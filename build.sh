#!/bin/bash

resourceGroupName="df2"

az bicep build \
  --file azuredeploy.bicep \
  --outfile azuredeploy.json

git commit -am . && git push

az deployment group create \
  --resource-group "${resourceGroupName}" \
  --template-uri "https://raw.githubusercontent.com/chgeuer/csv-blobs-via-datafactory-to-sql/main/azuredeploy.json" \
  --name "deploy" \
  --parameters sqlAdminPassword='SuperSecret123.-'
