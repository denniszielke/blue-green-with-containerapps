!/bin/bash

set -e

az extension add --source https://workerappscliextension.blob.core.windows.net/azure-cli-extension/containerapp-0.2.0-py2.py3-none-any.whl -y

# calculator properties
FRONTEND_APP_ID="js-calc-frontend"
BACKEND_APP_ID="js-calc-backend"

COLOR="green" # color highlighting
LAGGY="true" # if true the backend will cause random delays
BUGGY="false" # if true the backend will randomly generate 500 errors

# infrastructure deployment properties
DEPLOYMENT_NAME="$1" # here enter unique deployment name (ideally short and with letters for global uniqueness)
VERSION="$2" # version tag showing up in app
REGISTRY="$3"
AZURE_CORE_ONLY_SHOW_ERRORS="True"
CONTAINERAPPS_ENVIRONMENT_NAME="env-$DEPLOYMENT_NAME" # Name of the ContainerApp Environment
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

WORKER_BACKEND_APP_ID=$(az containerapp list -g $RESOURCE_GROUP --query "[?contains(name, '$BACKEND_APP_ID')].id" -o tsv)
if [ "$WORKER_BACKEND_APP_ID" = "" ]; then
    #az containerapp delete -g $RESOURCE_GROUP --name $BACKEND_APP_ID -y

    WORKER_BACKEND_APP_VERSION="backend $COLOR - $VERSION"

    echo "creating worker app $BACKEND_APP_ID of $WORKER_BACKEND_APP_VERSION"

    az containerapp create -e $CONTAINERAPPS_ENVIRONMENT_NAME -g $RESOURCE_GROUP \
     -i $REGISTRY/$BACKEND_APP_ID:$VERSION \
     -n $BACKEND_APP_ID \
     --cpu 0.5 --memory 1Gi \
     -v "LAGGY=$LAGGY,BUGGY=$BUGGY,PORT=8080,VERSION=$WORKER_BACKEND_APP_VERSION,INSTRUMENTATIONKEY=$AI_INSTRUMENTATION_KEY" \
     --ingress external \
     --location "$CONTAINERAPPS_LOCATION" \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_BACKEND_APP_VERSION,color=$COLOR" \
     --target-port 8080 --enable-dapr --dapr-app-id $BACKEND_APP_ID

    az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    WORKER_BACKEND_APP_ID=$(az containerapp show -g $RESOURCE_GROUP -n $BACKEND_APP_ID -o tsv --query id)
    WORKER_BACKEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)
    echo "created app $BACKEND_APP_ID running under $WORKER_BACKEND_FQDN"
else
    WORKER_BACKEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)
    echo "worker app $WORKER_BACKEND_APP_ID already exists running under $WORKER_BACKEND_FQDN"
    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table
    
    WORKER_BACKEND_APP_VERSION="backend $COLOR - $VERSION"

    echo "deploying new revision of $WORKER_BACKEND_APP_ID of $WORKER_BACKEND_APP_VERSION" 

    az containerapp create -e $CONTAINERAPPS_ENVIRONMENT_NAME -g $RESOURCE_GROUP \
     -i $REGISTRY/$BACKEND_APP_ID:$VERSION \
     -n $BACKEND_APP_ID \
     --cpu 0.5 --memory 1Gi \
     -v "LAGGY=$LAGGY,BUGGY=$BUGGY,PORT=8080,VERSION=$WORKER_BACKEND_APP_VERSION,INSTRUMENTATIONKEY=$AI_INSTRUMENTATION_KEY" \
     --ingress external \
     --location "$CONTAINERAPPS_LOCATION" \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_BACKEND_APP_VERSION,color=$COLOR" \
     --target-port 8080 --enable-dapr --dapr-app-id $BACKEND_APP_ID
     #--scale-rules "wa/httpscaler.json" --debug --verbose

    az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    NEW_BACKEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "reverse(sort_by([], &createdTime))| [0].name" -o tsv)

    WORKER_BACKEND_REVISION_FQDN=$(az containerapp revision show --resource-group $RESOURCE_GROUP --app $BACKEND_APP_ID --name $NEW_BACKEND_RELEASE_NAME --query "fqdn" -o tsv)

    echo "revision fqdn is $WORKER_BACKEND_REVISION_FQDN"

    sleep 3

    OLD_BACKEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "sort_by([], &createdTime)| [0].name" -o tsv)

    sleep 5

    echo "increasing traffic split to 80/20"

    az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=80,latest=20

    sleep 5
    
    echo "increasing traffic split to 60/40"
    az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=60,latest=40

    sleep 5
    
    echo "increasing traffic split to 40/60"
    az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=40,latest=60

    sleep 5
    
    echo "increasing traffic split to 20/80"
    az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=20,latest=80

    sleep 5
    
    echo "increasing traffic split to 0/100"
    az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=0,latest=100
    sleep 5

    az containerapp revision deactivate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $OLD_BACKEND_RELEASE_NAME 

    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    WORKER_BACKEND_FQDN=$WORKER_BACKEND_REVISION_FQDN

fi


WORKER_FRONTEND_APP_ID=$(az containerapp list -g $RESOURCE_GROUP --query "[?contains(name, '$FRONTEND_APP_ID')].id" -o tsv)
if [ "$WORKER_FRONTEND_APP_ID" = "" ]; then
    #az containerapp delete -g $RESOURCE_GROUP --name $FRONTEND_APP_ID -y

    WORKER_FRONTEND_APP_VERSION="frontend $COLOR - $VERSION"

    echo "creating worker app $FRONTEND_APP_ID of $WORKER_FRONTEND_APP_VERSION using $WORKER_BACKEND_FQDN"

    az containerapp create -e $CONTAINERAPPS_ENVIRONMENT_NAME -g $RESOURCE_GROUP \
     -i $REGISTRY/$FRONTEND_APP_ID:$VERSION \
     -n $FRONTEND_APP_ID \
     --cpu 0.5 --memory 1Gi \
     -v "LAGGY=$LAGGY,BUGGY=$BUGGY,PORT=8080,VERSION=$WORKER_FRONTEND_APP_VERSION,INSTRUMENTATIONKEY=$AI_INSTRUMENTATION_KEY,ENDPOINT=$WORKER_BACKEND_FQDN" \
     --ingress external \
     --location "$CONTAINERAPPS_LOCATION" \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_FRONTEND_APP_VERSION,color=$COLOR" \
     --target-port 8080  --enable-dapr --dapr-app-id $FRONTEND_APP_ID

    az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    WORKER_FRONTEND_APP_ID=$(az containerapp show -g $RESOURCE_GROUP -n $FRONTEND_APP_ID -o tsv --query id)
    WORKER_FRONTEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)
    echo "created app $FRONTEND_APP_ID running under $WORKER_FRONTEND_FQDN"
else
    WORKER_FRONTEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)
    echo "worker app env $WORKER_FRONTEND_APP_ID already exists"
    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table
    
    WORKER_FRONTEND_APP_VERSION="frontend $COLOR - $VERSION"

    echo "deploying new revision of $WORKER_FRONTEND_APP_ID of $WORKER_FRONTEND_APP_VERSION using $WORKER_BACKEND_FQDN" 

    az containerapp create -e $CONTAINERAPPS_ENVIRONMENT_NAME -g $RESOURCE_GROUP \
     -i $REGISTRY/$FRONTEND_APP_ID:$VERSION \
     -n $FRONTEND_APP_ID \
     --cpu 0.5 --memory 1Gi \
     -v "LAGGY=$LAGGY,BUGGY=$BUGGY,PORT=8080,VERSION=$WORKER_FRONTEND_APP_VERSION,INSTRUMENTATIONKEY=$AI_INSTRUMENTATION_KEY,ENDPOINT=$WORKER_BACKEND_FQDN" \
     --ingress external \
     --location "$CONTAINERAPPS_LOCATION" \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_FRONTEND_APP_VERSION,color=$COLOR" \
     --target-port 8080   --enable-dapr --dapr-app-id $FRONTEND_APP_ID

    az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table
    
    NEW_FRONTEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "reverse(sort_by([], &createdTime))| [0].name" -o tsv)

    WORKER_FRONTEND_REVISION_FQDN=$(az containerapp revision show --resource-group $RESOURCE_GROUP --app $FRONTEND_APP_ID --name $NEW_FRONTEND_RELEASE_NAME --query "fqdn" -o tsv)

    echo "revision fqdn is $WORKER_FRONTEND_REVISION_FQDN"

    sleep 3

    curl $WORKER_FRONTEND_REVISION_FQDN/ping

    sleep 2
    
    curl $WORKER_FRONTEND_REVISION_FQDN/ping

    OLD_FRONTEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "sort_by([], &createdTime)| [0].name" -o tsv)

    sleep 5

    echo "increasing traffic split to 80/20"

    az containerapp update --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=80,latest=20

    sleep 5
    
    echo "increasing traffic split to 60/40"
    az containerapp update --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=60,latest=40

    sleep 5
    
    echo "increasing traffic split to 40/60"
    az containerapp update --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=40,latest=60

    sleep 5
    
    echo "increasing traffic split to 20/80"
    az containerapp update --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=20,latest=80

    sleep 5
    
    echo "increasing traffic split to 0/100"
    az containerapp update --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=0,latest=100
    sleep 5

    az containerapp revision deactivate --app $FRONTEND_APP_ID -g $RESOURCE_GROUP --name $OLD_FRONTEND_RELEASE_NAME 

    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    WORKER_FRONTEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)
fi

echo "frontend running on $WORKER_FRONTEND_FQDN"
