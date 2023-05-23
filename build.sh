#!/bin/bash

resourceGroupName="df4"

az bicep build --file azuredeploy.bicep --stdout \
  | jq '(.resources[] | select(.type == "Microsoft.Resources/deploymentScripts")).dependsOn += ["trigger"]' \
  > azuredeploy.json

git commit -am . && git push

az group create --location northeurope --resource-group "${resourceGroupName}"

az deployment group create \
  --resource-group "${resourceGroupName}" \
  --template-uri "https://raw.githubusercontent.com/chgeuer/csv-blobs-via-datafactory-to-sql/main/azuredeploy.json" \
  --name "deploy" \
  --parameters sqlAdminPassword='SuperSecret123.-'
