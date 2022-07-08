!/bin/bash

set -e

# infrastructure deployment properties
DEPLOYMENT_NAME="$1" # here enter unique deployment name (ideally short and with letters for global uniqueness)
LOCATION="westeurope"

if [ $(az group exists --name $DEPLOYMENT_NAME) = false ]; then
    echo "creating resource group $DEPLOYMENT_NAME..."
    az group create -n $DEPLOYMENT_NAME -l $LOCATION -o none
    echo "resource group $DEPLOYMENT_NAME created"
else   
    echo "resource group $DEPLOYMENT_NAME already exists"
fi


az deployment group create -g $DEPLOYMENT_NAME -f ../deploy/main.bicep -p internalOnly=false