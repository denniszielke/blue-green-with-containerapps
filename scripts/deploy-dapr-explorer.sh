!/bin/bash

set -e

# az extension remove -n containerapp
# EXTENSION=$(az extension list --query "[?contains(name, 'containerapp')].name" -o tsv)
# if [ "$EXTENSION" = "" ]; then
    az extension add --source https://workerappscliextension.blob.core.windows.net/azure-cli-extension/containerapp-0.2.0-py2.py3-none-any.whl -y
# fi

# calculator properties
EXPLORER_APP_NAME="js-dapr-explorer"
CONTAINER_NAME="js-dapr-explorer"

# infrastructure deployment properties
DEPLOYMENT_NAME="$1" # here enter unique deployment name (ideally short and with letters for global uniqueness)
VERSION="$2" # version tag showing up in app
REGISTRY="$3"

SUBSCRIPTION_ID=$(az account show --query id -o tsv) 
AZURE_CORE_ONLY_SHOW_ERRORS="True"
CONTAINERAPPS_ENVIRONMENT_NAME="env-$DEPLOYMENT_NAME" # Name of the ContainerApp Environment
REDIS_NAME="rds-env-$DEPLOYMENT_NAME"
RESOURCE_GROUP=$DEPLOYMENT_NAME # here enter the resources group
CONTAINERAPPS_LOCATION="Central US EUAP"
AI_INSTRUMENTATION_KEY=""

az containerapp env list -g $RESOURCE_GROUP --query "[?contains(name, '$CONTAINERAPPS_ENVIRONMENT_NAME')].id" -o tsv

CONTAINER_APP_ENV_ID=$(az containerapp env list -g $RESOURCE_GROUP --query "[?contains(name, '$CONTAINERAPPS_ENVIRONMENT_NAME')].id" -o tsv)
if [ $CONTAINER_APP_ENV_ID = "" ]; then
    echo "container app env $CONTAINER_APP_ENV_ID does not exist - abort"
else
    echo "container app env $CONTAINER_APP_ENV_ID already exists"
fi

echo "deploying $VERSION from $REGISTRY"

echo "creating middleware components"
DAPR_COMPONENTS="" # --dapr-components ./middleware.yaml"
cat <<EOF > middleware.yaml
- name: ratelimit
  type: middleware.http.ratelimit
  version: v1
  metadata:
  - name: maxRequestsPerSecond
    value: 2
EOF


cat <<EOF > httpscaler.json
[{
    "name": "httpscalingrule",
     "type": "http",
    "metadata": {
        "concurrentRequests": "10"
    }
}]
EOF
EXPLORER_APP_VERSION="backend $COLOR - $VERSION"

EXPLORER_APP_ID=$(az containerapp list -g $RESOURCE_GROUP --query "[?contains(name, '$EXPLORER_APP_NAME')].id" -o tsv)
if [ "$EXPLORER_APP_ID" = "" ]; then
    echo "explorer app does not exist"

    echo "creating worker app $EXPLORER_APP_ID of $EXPLORER_APP_VERSION from $REGISTRY/$CONTAINER_NAME:$VERSION "

    az containerapp create -e $CONTAINERAPPS_ENVIRONMENT_NAME -g $RESOURCE_GROUP \
        -i $REGISTRY/$CONTAINER_NAME:$VERSION \
        -n $EXPLORER_APP_NAME \
        --cpu 0.5 --memory 1Gi \
        --location "$CONTAINERAPPS_LOCATION"  \
        -v "VERSION=$EXPLORER_APP_VERSION" \
        --ingress external \
        --max-replicas 3 --min-replicas 0 \
        --revisions-mode single \
        --tags "app=backend,version=$EXPLORER_APP_VERSION" \
        --target-port 3000 --scale-rules ./httpscaler.json --enable-dapr --dapr-app-id $EXPLORER_APP_NAME --dapr-app-port 3000 $DAPR_COMPONENTS


    az containerapp show --resource-group $RESOURCE_GROUP --name $EXPLORER_APP_NAME --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $EXPLORER_APP_NAME --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

else
    echo "explorer app does already exist - updating worker app $EXPLORER_APP_ID of $EXPLORER_APP_VERSION from $REGISTRY/$CONTAINER_NAME:$VERSION "

    az containerapp update -g $RESOURCE_GROUP \
    -i $REGISTRY/$CONTAINER_NAME:$VERSION \
    -n $EXPLORER_APP_NAME \
    --cpu 0.5 --memory 1Gi \
    -v "VERSION=$EXPLORER_APP_VERSION" \
    --ingress external \
    --max-replicas 3 --min-replicas 0 \
    --revisions-mode single \
    --tags "app=backend,version=$EXPLORER_APP_VERSION" \
    --target-port 3000 --scale-rules ./httpscaler.json --enable-dapr --dapr-app-id $EXPLORER_APP_NAME --dapr-app-port 3000 $DAPR_COMPONENTS


    az containerapp show --resource-group $RESOURCE_GROUP --name $EXPLORER_APP_NAME --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $EXPLORER_APP_NAME --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

fi


EXPLORER_APP_VERSION="backend $COLOR - $VERSION"


EXPLORER_APP_ID=$(az containerapp show -g $RESOURCE_GROUP -n $EXPLORER_APP_NAME -o tsv --query id)
EXPLORER_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $EXPLORER_APP_NAME --query "configuration.ingress.fqdn" -o tsv)
echo "created app $EXPLORER_APP_NAME running under $EXPLORER_FQDN"