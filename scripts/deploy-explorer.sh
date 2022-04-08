!/bin/bash

set -e

# az extension remove -n containerapp
EXTENSION=$(az extension list --query "[?contains(name, 'containerapp')].name" -o tsv)
if [ "$EXTENSION" = "" ]; then
    az extension add -n containerapp -y
fi

# calculator properties
EXPLORER_APP_NAME="js-explorer"
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
LOCATION=$(az group show -n $RESOURCE_GROUP --query location -o tsv)
az containerapp env list -g $RESOURCE_GROUP --query "[?contains(name, '$CONTAINERAPPS_ENVIRONMENT_NAME')].id" -o tsv

CONTAINER_APP_ENV_ID=$(az containerapp env list -g $RESOURCE_GROUP --query "[?contains(name, '$CONTAINERAPPS_ENVIRONMENT_NAME')].id" -o tsv)
if [ $CONTAINER_APP_ENV_ID = "" ]; then
    echo "container app env $CONTAINER_APP_ENV_ID does not exist - abort"
else
    echo "container app env $CONTAINER_APP_ENV_ID already exists"
fi

echo "deploying $VERSION from $REGISTRY"

EXPLORER_APP_VERSION="explorer $COLOR - $VERSION"

EXPLORER_APP_ID=$(az containerapp list -g $RESOURCE_GROUP --query "[?contains(name, '$EXPLORER_APP_NAME')].id" -o tsv)

cat <<EOF > containerapp.yaml
kind: containerapp
location: $LOCATION
name: $EXPLORER_APP_NAME
resourceGroup: $RESOURCE_GROUP
type: Microsoft.App/containerApps
tags:
    app: explorer
    version: $VERSION
properties:
    managedEnvironmentId: /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/managedEnvironments/$CONTAINERAPPS_ENVIRONMENT_NAME
    configuration:
        activeRevisionsMode: single
        ingress:
            external: True
            allowInsecure: false
            targetPort: 3000
            traffic:
            - latestRevision: true
              weight: 100
            transport: Auto
    template:
        revisionSuffix: $VERSION
        containers:
        - image: $REGISTRY/$CONTAINER_NAME:$VERSION
          name: $EXPLORER_APP_NAME
          env:
          - name: HTTP_PORT
            value: 3000
          - name: VERSION
            value: $VERSION
          resources:
              cpu: 0.5
              memory: 1Gi
        scale:
          minReplicas: 0
          maxReplicas: 4
          rules:
          - name: httprule
            custom:
              type: http
              metadata:
                concurrentRequests: 10
EOF

if [ "$EXPLORER_APP_ID" = "" ]; then
    echo "explorer app does not exist"

    echo "creating worker app $EXPLORER_APP_ID of $EXPLORER_APP_VERSION from $REGISTRY/$CONTAINER_NAME:$VERSION "

    az containerapp create  -n $EXPLORER_APP_NAME -g $RESOURCE_GROUP --yaml containerapp.yaml

    az containerapp show --resource-group $RESOURCE_GROUP --name $EXPLORER_APP_NAME --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $EXPLORER_APP_NAME --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

else
    echo "explorer app does already exist - updating worker app $EXPLORER_APP_ID of $EXPLORER_APP_VERSION from $REGISTRY/$CONTAINER_NAME:$VERSION "

    az containerapp update  -n $EXPLORER_APP_NAME -g $RESOURCE_GROUP --yaml containerapp.yaml

    az containerapp show --resource-group $RESOURCE_GROUP --name $EXPLORER_APP_NAME --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $EXPLORER_APP_NAME --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

fi


EXPLORER_APP_VERSION="backend $COLOR - $VERSION"


EXPLORER_APP_ID=$(az containerapp show -g $RESOURCE_GROUP -n $EXPLORER_APP_NAME -o tsv --query id)
EXPLORER_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $EXPLORER_APP_NAME --query "configuration.ingress.fqdn" -o tsv)
echo "created app $EXPLORER_APP_NAME running under $EXPLORER_FQDN"
