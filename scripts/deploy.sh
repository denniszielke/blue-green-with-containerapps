!/bin/bash

set -e

# az extension remove -n containerapp
# EXTENSION=$(az extension list --query "[?contains(name, 'containerapp')].name" -o tsv)
# if [ "$EXTENSION" = "" ]; then
    az extension add --source https://workerappscliextension.blob.core.windows.net/azure-cli-extension/containerapp-0.2.2-py2.py3-none-any.whl -y
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
LOCATION=$(az group show -n $RESOURCE_GROUP --query location -o tsv)
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

    echo "creating worker app $BACKEND_APP_ID of $WORKER_BACKEND_APP_VERSION from $REGISTRY/$BACKEND_APP_ID:$VERSION "


cat <<EOF > backend.yaml
kind: containerapp
location: $LOCATION
name: $BACKEND_APP_ID
resourceGroup: $RESOURCE_GROUP
type: Microsoft.Web/containerApps
tags:
    app: backend
    version: $WORKER_BACKEND_APP_VERSION
    color: $COLOR
properties:
    kubeEnvironmentId: /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/kubeEnvironments/$CONTAINERAPPS_ENVIRONMENT_NAME
    configuration:
        activeRevisionsMode: multiple
        ingress:
            external: True
            allowInsecure: false
            targetPort: 8080
            traffic:
            - latestRevision: true
              weight: 100
            transport: Auto
    template:
        revisionSuffix: $VERSION
        containers:
        - image: $REGISTRY/$BACKEND_APP_ID:$VERSION
          name: $BACKEND_APP_ID
          env:
          - name: VERSION
            value: $WORKER_BACKEND_APP_VERSION
          - name: PORT
            value: 8080
          resources:
              cpu: 0.5
              memory: 1Gi
        scale:
          minReplicas: 0
          maxReplicas: 10
          rules:
          - name: httprule
            custom:
              type: http
              metadata:
                concurrentRequests: 10
        dapr:
          enabled: true
          appPort: 8080
          appId: $BACKEND_APP_ID
EOF


    az containerapp create  -n $BACKEND_APP_ID -g $RESOURCE_GROUP --yaml backend.yaml

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

cat <<EOF > backend.yaml
kind: containerapp
location: $LOCATION
name: $BACKEND_APP_ID
resourceGroup: $RESOURCE_GROUP
type: Microsoft.Web/containerApps
tags:
    app: backend
    version: $WORKER_BACKEND_APP_VERSION
    color: $COLOR
properties:
    kubeEnvironmentId: /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/kubeEnvironments/$CONTAINERAPPS_ENVIRONMENT_NAME
    configuration:
        activeRevisionsMode: multiple
        ingress:
            external: True
            allowInsecure: false
            targetPort: 8080
            traffic:
            - latestRevision: true
              weight: 0
            - revisionName: $OLD_BACKEND_RELEASE_NAME
              weight: 100
            transport: Auto
    template:
        revisionSuffix: $VERSION
        containers:
        - image: $REGISTRY/$BACKEND_APP_ID:$VERSION
          name: $BACKEND_APP_ID
          env:
          - name: VERSION
            value: $WORKER_BACKEND_APP_VERSION
          - name: PORT
            value: 8080
          resources:
              cpu: 0.5
              memory: 1Gi
        scale:
          minReplicas: 0
          maxReplicas: 10
          rules:
          - name: httprule
            custom:
              type: http
              metadata:
                concurrentRequests: 10
        dapr:
          enabled: true
          appPort: 8080
          appId: $BACKEND_APP_ID
EOF

    az containerapp update  -n $BACKEND_APP_ID -g $RESOURCE_GROUP --yaml backend.yaml

    az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    NEW_BACKEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}[?Active!=`false`], &Created))| [0].Revision' -o tsv)

    WORKER_BACKEND_REVISION_FQDN=$(az containerapp revision show --resource-group $RESOURCE_GROUP --app $BACKEND_APP_ID --name $NEW_BACKEND_RELEASE_NAME --query "fqdn" -o tsv)

    echo "revision fqdn is $WORKER_BACKEND_REVISION_FQDN"

    sleep 10
    
    echo "here we can make a decision to abort and deactivate the new release"

    RES_BACKEND=$(curl --write-out "%{http_code}\n" -f -s $WORKER_BACKEND_REVISION_FQDN/ping --output backend.txt )
    echo $RES_BACKEND 

    if [ $RES_BACKEND = "301" ]; then
       
        echo "backend is up and running and responded with $RES_BACKEND"
        # echo "increasing traffic split to 50/50"
        # az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_BACKEND_RELEASE_NAME=50,latest=50

        # sleep 10
        
        # curl $WORKER_BACKEND_REVISION_FQDN/ping

        # sleep 10
        
        echo "increasing traffic split to 0/100"
        az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_BACKEND_RELEASE_NAME=0,latest=100
        sleep 5

        echo "deactivating $OLD_BACKEND_RELEASE_NAME"

        az containerapp revision deactivate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $OLD_BACKEND_RELEASE_NAME 

        sleep 5

        az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

        WORKER_BACKEND_FQDN=$WORKER_BACKEND_REVISION_FQDN

    else
        echo "backend responded with $RES_BACKEND - deployment failed"
        
        echo "bringing back the old revision $OLD_BACKEND_RELEASE_NAME"
        az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_BACKEND_RELEASE_NAME=100,latest=0
        
        sleep 5

        echo "deleting latest backend revision $NEW_BACKEND_RELEASE_NAME"
        az containerapp revision deactivate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $NEW_BACKEND_RELEASE_NAME 

        exit
    fi

fi


echo "checking redis components"

REDIS_ID=$(az redis list -g $RESOURCE_GROUP --query "[?contains(name, '$REDIS_NAME')].id" -o tsv)
if [ "$REDIS_ID" = "" ]; then
    echo "no redis found"
else

    echo "found redis instance $REDIS_ID"

REDIS_HOST=$(az redis show -g $RESOURCE_GROUP --name $REDIS_NAME --query "hostName" -o tsv)
REDIS_KEY=$(az redis list-keys -g $RESOURCE_GROUP --name $REDIS_NAME --query "primaryKey" -o tsv )

fi


WORKER_FRONTEND_APP_ID=$(az containerapp list -g $RESOURCE_GROUP --query "[?contains(name, '$FRONTEND_APP_ID')].id" -o tsv)
if [ "$WORKER_FRONTEND_APP_ID" = "" ]; then
    #az containerapp delete -g $RESOURCE_GROUP --name $FRONTEND_APP_ID -y

    WORKER_FRONTEND_APP_VERSION="frontend $COLOR - $VERSION"

    echo "creating worker app $FRONTEND_APP_ID of $WORKER_FRONTEND_APP_VERSION using $WORKER_BACKEND_FQDN"

cat <<EOF > frontend.yaml
kind: containerapp
location: $LOCATION
name: $FRONTEND_APP_ID
resourceGroup: $RESOURCE_GROUP
type: Microsoft.Web/containerApps
tags:
    app: frontend
    version: $WORKER_FRONTEND_APP_VERSION
    color: $COLOR
properties:
    kubeEnvironmentId: /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/kubeEnvironments/$CONTAINERAPPS_ENVIRONMENT_NAME
    configuration:
        activeRevisionsMode: multiple
        ingress:
            external: True
            allowInsecure: false
            targetPort: 8080
            traffic:
            - latestRevision: true
              weight: 100
            transport: Auto
    template:
        revisionSuffix: $VERSION
        containers:
        - image: $REGISTRY/$FRONTEND_APP_ID:$VERSION
          name: $FRONTEND_APP_ID
          env:
          - name: VERSION
            value: $WORKER_FRONTEND_APP_VERSION
          - name: PORT
            value: 8080
          - name: ENDPOINT
            value: http://localhost:3500/v1.0/invoke/$BACKEND_APP_ID/method
          - name: CACHEENDPOINT
            value: http://localhost:3500/v1.0/state/redis
          resources:
              cpu: 0.5
              memory: 1Gi
        scale:
          minReplicas: 0
          maxReplicas: 10
          rules:
          - name: httprule
            custom:
              type: http
              metadata:
                concurrentRequests: 10
        dapr:
          enabled: true
          appPort: 8080
          appId: $FRONTEND_APP_ID
          components:
          - name: redis
            type: state.redis
            version: v1
            metadata:
            - name: redisHost 
              value: $REDIS_HOST:6379
            - name: redisPassword
              value: $REDIS_KEY
EOF

    az containerapp create  -n $FRONTEND_APP_ID -g $RESOURCE_GROUP --yaml frontend.yaml

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

cat <<EOF > frontend.yaml
kind: containerapp
location: $LOCATION
name: $FRONTEND_APP_ID
resourceGroup: $RESOURCE_GROUP
type: Microsoft.Web/containerApps
tags:
    app: frontend
    version: $WORKER_FRONTEND_APP_VERSION
    color: $COLOR
properties:
    kubeEnvironmentId: /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/kubeEnvironments/$CONTAINERAPPS_ENVIRONMENT_NAME
    configuration:
        activeRevisionsMode: multiple
        ingress:
            external: True
            allowInsecure: false
            targetPort: 8080
            traffic:
            - latestRevision: true
              weight: 0
            - revisionName: $OLD_FRONTEND_RELEASE_NAME
              weight: 100
            transport: Auto
    template:
        revisionSuffix: $VERSION
        containers:
        - image: $REGISTRY/$FRONTEND_APP_ID:$VERSION
          name: $FRONTEND_APP_ID
          env:
          - name: VERSION
            value: $WORKER_FRONTEND_APP_VERSION
          - name: PORT
            value: 8080
          - name: ENDPOINT
            value: http://localhost:3500/v1.0/invoke/$BACKEND_APP_ID/method
          - name: CACHEENDPOINT
            value: http://localhost:3500/v1.0/state/redis
          resources:
              cpu: 0.5
              memory: 1Gi
        scale:
          minReplicas: 0
          maxReplicas: 10
          rules:
          - name: httprule
            custom:
              type: http
              metadata:
                concurrentRequests: 10
        dapr:
          enabled: true
          appPort: 8080
          appId: $FRONTEND_APP_ID
          components:
          - name: redis
            type: state.redis
            version: v1
            metadata:
            - name: redisHost 
              value: $REDIS_HOST:6379
            - name: redisPassword
              value: $REDIS_KEY
EOF

    az containerapp update  -n $FRONTEND_APP_ID -g $RESOURCE_GROUP --yaml frontend.yaml

    az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "{FQDN:configuration.ingress.fqdn,ProvisioningState:provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

    NEW_FRONTEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}[?Active!=`false`], &Created))| [0].Revision' -o tsv)

    WORKER_FRONTEND_REVISION_FQDN=$(az containerapp revision show --resource-group $RESOURCE_GROUP --app $FRONTEND_APP_ID --name $NEW_FRONTEND_RELEASE_NAME --query "fqdn" -o tsv)

    echo "revision fqdn is $WORKER_FRONTEND_REVISION_FQDN"

    echo "here we can make a decision to abort and deactivate the new release"

    sleep 10

    RES_FRONTEND=$(curl --write-out "%{http_code}\n" -f -s $WORKER_FRONTEND_REVISION_FQDN/ping --output frontend.txt )
    echo $RES_FRONTEND

    if [ $RES_FRONTEND = "301" ]; then

        echo "frontend is up and running and responded with $RES_FRONTEND"
        # echo "increasing traffic split to 50/50"
        # az containerapp update --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=50,latest=50

        # sleep 10
        
        echo "increasing traffic split to 0/100"
        az containerapp update --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=0,latest=100
        sleep 5

        echo "deactivating $OLD_FRONTEND_RELEASE_NAME"
        az containerapp revision deactivate --app $FRONTEND_APP_ID -g $RESOURCE_GROUP --name $OLD_FRONTEND_RELEASE_NAME 

        sleep 5

        az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:replicas,Active:active,Created:createdTime,FQDN:fqdn}" -o table

        WORKER_FRONTEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "configuration.ingress.fqdn" -o tsv)

    else
        echo "frontend responded with $RES_FRONTEND - deployment failed"

        echo "activating previous backend revison $OLD_BACKEND_RELEASE_NAME again"
        az containerapp revision activate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $OLD_BACKEND_RELEASE_NAME 
        
        sleep 5

        az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_BACKEND_RELEASE_NAME=100,latest=0

        sleep 5

        echo "deleting latest backend revision $NEW_BACKEND_RELEASE_NAME"
        az containerapp revision deactivate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $NEW_BACKEND_RELEASE_NAME 

        echo "bringing back the original frontend release $OLD_FRONTEND_RELEASE_NAME"
        az containerapp update --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=100,latest=0

        sleep 5

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
