!/bin/bash

set -e

# infrastructure deployment properties
DEPLOYMENT_NAME="$1" # here enter unique deployment name (ideally short and with letters for global uniqueness)
VERSION="$2" # version tag showing up in app
REGISTRY="$3"

az deployment group create -g $DEPLOYMENT_NAME -f ../deploy/apps.bicep \
          -p explorerImageTag=$VERSION \
          -p calculatorImageTag=$VERSION \
          -p containerRegistryOwner=$REGISTRY