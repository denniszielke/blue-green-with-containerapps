!/bin/bash

set -e

# infrastructure deployment properties
DEPLOYMENT_NAME="$1" # here enter unique deployment name (ideally short and with letters for global uniqueness)
LOCATION="$2"

if [ $(az group exists --name $DEPLOYMENT_NAME) = false ]; then
    echo "creating resource group $DEPLOYMENT_NAME..."
    az group create -n $DEPLOYMENT_NAME -l $LOCATION -o none
    echo "resource group $DEPLOYMENT_NAME created"
else   
    echo "resource group $DEPLOYMENT_NAME already exists"
fi


RESULT=$(az deployment group create -g $DEPLOYMENT_NAME -f ../deploy/main.bicep -p internalOnly=false --query properties.outputs.result)

echo $RESULT

#PRIVATE_LINK_ENDPOINT_CONNECTION_ID=$(echo $RESULT | jq -r '.value.privateLinkEndpointConnectionId')
#FQDN=$(echo $RESULT | jq -r '.value.fqdn')

#echo "Private link endpoint connection ID: $PRIVATE_LINK_ENDPOINT_CONNECTION_ID"
#az network private-endpoint-connection approve --id $PRIVATE_LINK_ENDPOINT_CONNECTION_ID --description "Approved by deployment script"

#echo "FrontDoor FQDN: https://$FQDN ---"