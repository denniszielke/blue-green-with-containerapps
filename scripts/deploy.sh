!/bin/bash

set -e

# az extension remove -n containerapp
# EXTENSION=$(az extension list --query "[?contains(name, 'containerapp')].name" -o tsv)
# if [ "$EXTENSION" = "" ]; then
    az extension add --source https://workerappscliextension.blob.core.windows.net/azure-cli-extension/containerapp-0.2.0-py2.py3-none-any.whl -y
# fi

# calculator properties
FRONTEND_APP_ID="js-calc-frontend"
BACKEND_APP_ID="js-calc-backend"

COLOR="blue" # color highlighting
LAGGY="true" # if true the backend will cause random delays
BUGGY="false" # if true the backend will randomly generate 500 errors

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

echo "creating redis components"

REDIS_COMMAND=" --dapr-components ./redis.yaml"
REDIS_ID=$(az redis list -g $RESOURCE_GROUP --query "[?contains(name, '$REDIS_NAME')].id" -o tsv)
if [ "$REDIS_ID" = "" ]; then
    REDIS_COMMAND=""
else

REDIS_HOST=$(az redis show -g $RESOURCE_GROUP --name $REDIS_NAME --query "hostName" -o tsv)
REDIS_KEY=$(az redis list-keys -g $RESOURCE_GROUP --name $REDIS_NAME --query "primaryKey" -o tsv )

cat <<EOF > redis.yaml
- name: redis
  type: state.redis
  version: v1
  metadata:
  - name: redisHost 
    value: $REDIS_HOST:6379
  - name: redisPassword
    value: $REDIS_KEY
EOF

fi

cat <<EOF > httpscaler.json
[{
    "name": "httpscalingrule",
     "type": "http",
    "metadata": {
        "concurrentRequests": "10"
    }
}]
EOF

WORKER_BACKEND_APP_ID=$(az containerapp list -g $RESOURCE_GROUP --query "[?contains(name, '$BACKEND_APP_ID')].id" -o tsv)
if [ "$WORKER_BACKEND_APP_ID" = "" ]; then
    #az containerapp delete -g $RESOURCE_GROUP --name $BACKEND_APP_ID -y

    WORKER_BACKEND_APP_VERSION="backend $COLOR - $VERSION"

    echo "creating worker app $BACKEND_APP_ID of $WORKER_BACKEND_APP_VERSION from $REGISTRY/$BACKEND_APP_ID:$VERSION "

    az containerapp create -e $CONTAINERAPPS_ENVIRONMENT_NAME -g $RESOURCE_GROUP \
     -i $REGISTRY/$BACKEND_APP_ID:$VERSION \
     -n $BACKEND_APP_ID \
     --cpu 0.5 --memory 1Gi \
     --location "$CONTAINERAPPS_LOCATION"  \
     -v "VERSION=$WORKER_BACKEND_APP_VERSION" \
     --ingress external \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_BACKEND_APP_VERSION,color=$COLOR" \
     --target-port 8080 --scale-rules ./httpscaler.json --enable-dapr --dapr-app-id $BACKEND_APP_ID --dapr-app-port 8080 $REDIS_COMMAND


    az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    WORKER_BACKEND_APP_ID=$(az containerapp show -g $RESOURCE_GROUP -n $BACKEND_APP_ID -o tsv --query id)
    WORKER_BACKEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)
    echo "created app $BACKEND_APP_ID running under $WORKER_BACKEND_FQDN"
else
    echo "making sure that there is only one active revision out there"

    EXTRA_REVISION=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}[?Active!=`false`], &Created))| [1].Revision' -o tsv)   

    while [ "$EXTRA_REVISION" != "" ]; 
    do
        echo "deactivating extra revision $EXTRA_REVISION"
        az containerapp revision deactivate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $EXTRA_REVISION;
        EXTRA_REVISION=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}[?Active!=`false`], &Created))| [1].Revision' -o tsv)   
    done

    IS_GREEN=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Version:template.containers[0].env[0].value,Created:createdTime}[?Active!=`false`], &Created))| [0].Version' -o tsv)   
    echo "existing app is using color $IS_GREEN"
    COLOR="green"
    if  grep -q "green" <<< "$IS_GREEN" ; then
        COLOR="blue"
        echo "using blue"
    fi

    WORKER_BACKEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)
    echo "worker app $WORKER_BACKEND_APP_ID already exists running under $WORKER_BACKEND_FQDN"
    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    OLD_BACKEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}[?Active!=`false`], &Created))| [0].Revision' -o tsv)

    WORKER_BACKEND_APP_VERSION="backend $COLOR - $VERSION"

    echo "deploying new revision of $WORKER_BACKEND_APP_ID of $WORKER_BACKEND_APP_VERSION" 

    az containerapp update -g $RESOURCE_GROUP \
     -i $REGISTRY/$BACKEND_APP_ID:$VERSION \
     -n $BACKEND_APP_ID \
     --cpu 0.5 --memory 1Gi \
      -v "VERSION=$WORKER_BACKEND_APP_VERSION" \
     --ingress external \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_BACKEND_APP_VERSION,color=$COLOR" \
     --target-port 8080 --scale-rules ./httpscaler.json --enable-dapr --dapr-app-id $BACKEND_APP_ID --dapr-app-port 8080 $REDIS_COMMAND

    az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    NEW_BACKEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}[?Active!=`false`], &Created))| [0].Revision' -o tsv)

    WORKER_BACKEND_REVISION_FQDN=$(az containerapp revision show --resource-group $RESOURCE_GROUP --app $BACKEND_APP_ID --name $NEW_BACKEND_RELEASE_NAME --query "fqdn" -o tsv)

    echo "revision fqdn is $WORKER_BACKEND_REVISION_FQDN"

    sleep 10
    
    echo "here we can make a decision to abort and deactivate the new release"

    RES_BACKEND=$(curl -f -s $WORKER_BACKEND_REVISION_FQDN/ping)

    if  grep -q "pong" <<< "$RES_BACKEND" ; then
       
        echo "increasing traffic split to 50/50"
        az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_BACKEND_RELEASE_NAME=50,latest=50

        sleep 10
        
        curl $WORKER_BACKEND_REVISION_FQDN/ping

        sleep 10
        
        echo "increasing traffic split to 0/100"
        az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_BACKEND_RELEASE_NAME=0,latest=100
        sleep 5

        az containerapp revision deactivate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $OLD_BACKEND_RELEASE_NAME 

        az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

        WORKER_BACKEND_FQDN=$WORKER_BACKEND_REVISION_FQDN

    else
        echo "backend responded with $RES_BACKEND - deployment failed"

        echo "deleting latest backend revision $NEW_BACKEND_RELEASE_NAME"
        az containerapp revision deactivate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $NEW_BACKEND_RELEASE_NAME 

        exit
    fi

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
     --location "$CONTAINERAPPS_LOCATION"  \
     -v "ENDPOINT=http://localhost:3500/v1.0/invoke/$BACKEND_APP_ID/method,VERSION=$WORKER_FRONTEND_APP_VERSION,CACHEENDPOINT=http://localhost:3500/v1.0/state/redis" \
     --ingress external \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_FRONTEND_APP_VERSION,color=$COLOR" \
     --target-port 8080 --scale-rules ./httpscaler.json --enable-dapr --dapr-app-id $FRONTEND_APP_ID --dapr-app-port 8080 

    az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    WORKER_FRONTEND_APP_ID=$(az containerapp show -g $RESOURCE_GROUP -n $FRONTEND_APP_ID -o tsv --query id)
    WORKER_FRONTEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)
    echo "created app $FRONTEND_APP_ID running under $WORKER_FRONTEND_FQDN"
else

    echo "making sure that there is only one active revision out there"

    EXTRA_REVISION=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}[?Active!=`false`], &Created))| [1].Revision' -o tsv)   

    while [ "$EXTRA_REVISION" != "" ]; 
    do
        echo "deactivating extra revision $EXTRA_REVISION"
        az containerapp revision deactivate --app $FRONTEND_APP_ID -g $RESOURCE_GROUP --name $EXTRA_REVISION;
        EXTRA_REVISION=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}[?Active!=`false`], &Created))| [1].Revision' -o tsv)   
    done

    COLOR="green"
    IS_GREEN=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Version:template.containers[0].env[0].value,Created:createdTime}[?Active!=`false`], &Created))| [0].Version' -o tsv)   
    echo "existing app is using color $IS_GREEN"
    if  grep -q "green" <<< "$IS_GREEN" ; then
        COLOR="blue"
        echo "using blue"
    fi

    WORKER_FRONTEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)
    echo "worker app $WORKER_FRONTEND_APP_ID already exists running under $WORKER_FRONTEND_FQDN"
    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    OLD_FRONTEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}[?Active!=`false`], &Created))| [0].Revision' -o tsv)

    WORKER_FRONTEND_APP_VERSION="frontend $COLOR - $VERSION"

    echo "deploying new revision of $WORKER_FRONTEND_APP_ID of $WORKER_FRONTEND_APP_VERSION" 

    az containerapp update -g $RESOURCE_GROUP \
     -i $REGISTRY/$FRONTEND_APP_ID:$VERSION \
     -n $FRONTEND_APP_ID \
     --cpu 0.5 --memory 1Gi \
     -v "ENDPOINT=http://localhost:3500/v1.0/invoke/$BACKEND_APP_ID/method,VERSION=$WORKER_FRONTEND_APP_VERSION,CACHEENDPOINT=http://localhost:3500/v1.0/state/redis" \
     --ingress external \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_FRONTEND_APP_VERSION,color=$COLOR" \
     --target-port 8080 --scale-rules ./httpscaler.json --enable-dapr --dapr-app-id $FRONTEND_APP_ID --dapr-app-port 8080 

    az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    NEW_FRONTEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}[?Active!=`false`], &Created))| [0].Revision' -o tsv)

    WORKER_FRONTEND_REVISION_FQDN=$(az containerapp revision show --resource-group $RESOURCE_GROUP --app $FRONTEND_APP_ID --name $NEW_FRONTEND_RELEASE_NAME --query "fqdn" -o tsv)

    echo "revision fqdn is $WORKER_FRONTEND_REVISION_FQDN"

    echo "here we can make a decision to abort and deactivate the new release"

    sleep 10
    
    RES_FRONTEND=$(curl -f -s $WORKER_FRONTEND_REVISION_FQDN/ping)

    if  grep -q "pong" <<< "$RES_FRONTEND" ; then

        echo "increasing traffic split to 50/50"
        az containerapp update --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=50,latest=50

        sleep 10
        
        echo "increasing traffic split to 0/100"
        az containerapp update --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=0,latest=100
        sleep 5

        az containerapp revision deactivate --app $FRONTEND_APP_ID -g $RESOURCE_GROUP --name $OLD_FRONTEND_RELEASE_NAME 

        az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

        WORKER_FRONTEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)

    else
        echo "frontend responded with $RES_FRONTEND - deployment failed"

        echo "activating previous backend revison $OLD_BACKEND_RELEASE_NAME again"
        az containerapp revision activate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $OLD_BACKEND_RELEASE_NAME 

        sleep 5

        echo "deleting latest backend revision $NEW_BACKEND_RELEASE_NAME"
        az containerapp revision deactivate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $NEW_BACKEND_RELEASE_NAME 

        echo "deleting latest frontend revision $NEW_FRONTEND_RELEASE_NAME again"
        az containerapp revision deactivate --app $FRONTEND_APP_ID -g $RESOURCE_GROUP --name $NEW_FRONTEND_RELEASE_NAME 
        exit
    fi
    
fi

echo "frontend running on $WORKER_FRONTEND_FQDN"

ID=$(uuidgen)
ANNOTATIONNAME="release $VERSION"
EVENTTIME=$(date '+%Y-%m-%dT%H:%M:%S')  #$(printf '%(%Y-%m-%dT%H:%M:%S)T')
CATEGORY="Deployment"

RESOURCE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/microsoft.insights/components/appins-env-$DEPLOYMENT_NAME"

JSON_STRING=$( jq -n -c \
                  --arg id "$ID" \
                  --arg an "$ANNOTATIONNAME" \
                  --arg et "$EVENTTIME" \
                  --arg cg "$CATEGORY" \
                  '{Id: $id, AnnotationName: $an, EventTime: $et, Category: $cg}' ) 
                  
JSON_STRING=$(echo $JSON_STRING | tr '"' "'")
echo $JSON_STRING

az rest --method put --uri "$RESOURCE/Annotations?api-version=2015-05-01" --body "$JSON_STRING"