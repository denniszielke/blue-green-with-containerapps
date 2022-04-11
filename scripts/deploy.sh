!/bin/bash

set -e

# az extension remove -n containerapp
EXTENSION=$(az extension list --query "[?contains(name, 'containerapp')].name" -o tsv)
if [ "$EXTENSION" = "" ]; then
    az extension add -n containerapp -y
fi

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
LOCATION=$(az group show -n $RESOURCE_GROUP --query location -o tsv)
az containerapp env list -g $RESOURCE_GROUP --query "[?contains(name, '$CONTAINERAPPS_ENVIRONMENT_NAME')].id" -o tsv

CONTAINER_APP_ENV_ID=$(az containerapp env list -g $RESOURCE_GROUP --query "[?contains(name, '$CONTAINERAPPS_ENVIRONMENT_NAME')].id" -o tsv)
if [ $CONTAINER_APP_ENV_ID = "" ]; then
    echo "container app env $CONTAINER_APP_ENV_ID does not exist - abort"
else
    echo "container app env $CONTAINER_APP_ENV_ID already exists"
fi

echo "deploying $VERSION from $REGISTRY"

AI_INSTRUMENTATION_KEY=$(az resource show -g $RESOURCE_GROUP -n appins-env-$DEPLOYMENT_NAME --resource-type "Microsoft.Insights/components" --query properties.InstrumentationKey -o tsv | tr -d '[:space:]')

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
type: Microsoft.App/containerApps
tags:
    app: backend
    version: $WORKER_BACKEND_APP_VERSION
    color: $COLOR
properties:
    managedEnvironmentId: /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/managedEnvironments/$CONTAINERAPPS_ENVIRONMENT_NAME
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
        dapr:
          enabled: true
          appPort: 8080
          appId: $BACKEND_APP_ID
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
          - name: INSTRUMENTATIONKEY
            value: $AI_INSTRUMENTATION_KEY
          resources:
              cpu: 1
              memory: 2Gi
        scale:
          minReplicas: 1
          maxReplicas: 4
          rules:
          - name: backendrule
            custom:
              type: http
              metadata:
                concurrentRequests: 10
EOF


    az containerapp create  -n $BACKEND_APP_ID -g $RESOURCE_GROUP --yaml backend.yaml

    az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "{FQDN:properties.configuration.ingress.fqdn,ProvisioningState:properties.provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}" -o table

    WORKER_BACKEND_APP_ID=$(az containerapp show -g $RESOURCE_GROUP -n $BACKEND_APP_ID -o tsv --query id)
    WORKER_BACKEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "properties.configuration.ingress.fqdn" -o tsv)
    echo "created app $BACKEND_APP_ID running under $WORKER_BACKEND_FQDN"
else
    echo "making sure that there is only one active revision out there"

    EXTRA_REVISION=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}[?Active!=`false`], &Created))| [1].Revision' -o tsv)   

    while [ "$EXTRA_REVISION" != "" ]; 
    do
        echo "deactivating extra revision $EXTRA_REVISION"
        az containerapp revision deactivate --app $BACKEND_APP_ID -g $RESOURCE_GROUP --name $EXTRA_REVISION;
        EXTRA_REVISION=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}[?Active!=`false`], &Created))| [1].Revision' -o tsv)   
    done

    IS_GREEN=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Version:properties.template.containers[0].env[0].value,Created:properties.createdTime}[?Active!=`false`], &Created))| [0].Version' -o tsv)   
    echo "existing app is using color $IS_GREEN"
    COLOR="green"
    if  grep -q "green" <<< "$IS_GREEN" ; then
        COLOR="blue"
        echo "using blue"
    fi

    WORKER_BACKEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "properties.configuration.ingress.fqdn" -o tsv)
    echo "worker app $WORKER_BACKEND_APP_ID already exists running under $WORKER_BACKEND_FQDN"
    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}" -o table

    OLD_BACKEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}[?Active!=`false`], &Created))| [0].Revision' -o tsv)

    echo "existing release has name $OLD_BACKEND_RELEASE_NAME"

    WORKER_BACKEND_APP_VERSION="backend $COLOR - $VERSION"

    echo "deploying new revision of $WORKER_BACKEND_APP_ID of $WORKER_BACKEND_APP_VERSION" 

cat <<EOF > backend.yaml
kind: containerapp
location: $LOCATION
name: $BACKEND_APP_ID
resourceGroup: $RESOURCE_GROUP
type: Microsoft.App/containerApps
tags:
    app: backend
    version: $WORKER_BACKEND_APP_VERSION
    color: $COLOR
properties:
    managedEnvironmentId: /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/managedEnvironments/$CONTAINERAPPS_ENVIRONMENT_NAME
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
        dapr:
          enabled: true
          appPort: 8080
          appId: $BACKEND_APP_ID
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
          - name: INSTRUMENTATIONKEY
            value: $AI_INSTRUMENTATION_KEY
          resources:
              cpu: 1
              memory: 2Gi
        scale:
          minReplicas: 1
          maxReplicas: 4
          rules:
          - name: backendrule
            custom:
              type: http
              metadata:
                concurrentRequests: 10
EOF

    az containerapp update  -n $BACKEND_APP_ID -g $RESOURCE_GROUP --yaml backend.yaml

    az containerapp show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --query "{FQDN:properties.configuration.ingress.fqdn,ProvisioningState:properties.provisioningState}" --out table

    echo "$BACKEND_APP_ID has the following revisions:"

    az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}" -o table

    NEW_BACKEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}[?Active!=`false`], &Created))| [0].Revision' -o tsv)

    echo "new revision is named $NEW_BACKEND_RELEASE_NAME"

    WORKER_BACKEND_REVISION_FQDN=$(az containerapp revision show --resource-group $RESOURCE_GROUP --name $BACKEND_APP_ID --revision $NEW_BACKEND_RELEASE_NAME --query "properties.fqdn" -o tsv)

    echo "new revision fqdn is $WORKER_BACKEND_REVISION_FQDN"

    sleep 10
    
    echo "here we can make a decision to abort and deactivate the new release"

    RES_BACKEND=$(curl --write-out "%{http_code}\n" -f -s $WORKER_BACKEND_REVISION_FQDN/ping --output backend.txt )
    echo $RES_BACKEND 

    if [ $RES_BACKEND = "301" ]; then
       
        echo "backend is up and running and responded with $RES_BACKEND"
        
        # echo "increasing traffic split to 0/100"
        az containerapp ingress traffic set --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_BACKEND_RELEASE_NAME=0 $NEW_BACKEND_RELEASE_NAME=100
        sleep 5

        echo "deactivating $OLD_BACKEND_RELEASE_NAME"

        az containerapp revision deactivate --name $BACKEND_APP_ID -g $RESOURCE_GROUP --revision $OLD_BACKEND_RELEASE_NAME 

        sleep 5

        az containerapp revision list -g $RESOURCE_GROUP -n $BACKEND_APP_ID --query "[].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}" -o table

        WORKER_BACKEND_FQDN=$WORKER_BACKEND_REVISION_FQDN

        echo "production revision $NEW_BACKEND_RELEASE_NAME is now $WORKER_BACKEND_FQDN"

    else
        echo "backend responded with $RES_BACKEND - deployment failed"
        
        echo "bringing back the old revision $OLD_BACKEND_RELEASE_NAME"
        az containerapp ingress traffic set --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_BACKEND_RELEASE_NAME=100 latest=0
        
        sleep 5

        echo "deleting latest backend revision $NEW_BACKEND_RELEASE_NAME"
        az containerapp revision deactivate --name $BACKEND_APP_ID -g $RESOURCE_GROUP --revision $NEW_BACKEND_RELEASE_NAME 

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

cat <<EOF > redis.yaml
componentType: state.redis
version: v1
metadata:
- name: redisHost 
  value: $REDIS_HOST:6379
- name: redisPassword
  value: $REDIS_KEY
scopes:
  - $FRONTEND_APP_ID
EOF

az containerapp env dapr-component set --dapr-component-name redis --name $CONTAINERAPPS_ENVIRONMENT_NAME -g $RESOURCE_GROUP --yaml redis.yaml

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
type: Microsoft.App/containerApps
tags:
    app: frontend
    version: $WORKER_FRONTEND_APP_VERSION
    color: $COLOR
properties:
    managedEnvironmentId: /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/managedEnvironments/$CONTAINERAPPS_ENVIRONMENT_NAME
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
        dapr:
          enabled: true
          appPort: 8080
          appId: $FRONTEND_APP_ID
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
          - name: INSTRUMENTATIONKEY
            value: $AI_INSTRUMENTATION_KEY
          resources:
              cpu: 1
              memory: 2Gi
        scale:
          minReplicas: 1
          maxReplicas: 4
          rules:
          - name: frontendrule
            custom:
              type: http
              metadata:
                concurrentRequests: 10
EOF

    az containerapp create  -n $FRONTEND_APP_ID -g $RESOURCE_GROUP --yaml frontend.yaml

    az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "{FQDN:properties.configuration.ingress.fqdn,ProvisioningState:properties.provisioningState}" --out table

    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}" -o table

    WORKER_FRONTEND_APP_ID=$(az containerapp show -g $RESOURCE_GROUP -n $FRONTEND_APP_ID -o tsv --query id)
    WORKER_FRONTEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "properties.configuration.ingress.fqdn" -o tsv)
    echo "created app $FRONTEND_APP_ID running under $WORKER_FRONTEND_FQDN"
else

    echo "making sure that there is only one active revision out there"

    EXTRA_REVISION=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}[?Active!=`false`], &Created))| [1].Revision' -o tsv)   

    while [ "$EXTRA_REVISION" != "" ]; 
    do
        echo "deactivating extra revision $EXTRA_REVISION"
        az containerapp revision deactivate --app $FRONTEND_APP_ID -g $RESOURCE_GROUP --name $EXTRA_REVISION;
        EXTRA_REVISION=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}[?Active!=`false`], &Created))| [1].Revision' -o tsv)   
    done

    COLOR="green"
    IS_GREEN=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Version:properties.template.containers[0].env[0].value,Created:properties.createdTime}[?Active!=`false`], &Created))| [0].Version' -o tsv)   
    echo "existing app is using color $IS_GREEN"
    if  grep -q "green" <<< "$IS_GREEN" ; then
        COLOR="blue"
        echo "using blue"
    fi

    WORKER_FRONTEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "properties.configuration.ingress.fqdn" -o tsv)
    echo "worker app $WORKER_FRONTEND_APP_ID already exists running under $WORKER_FRONTEND_FQDN"
    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}" -o table

    OLD_FRONTEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}[?Active!=`false`], &Created))| [0].Revision' -o tsv)

    WORKER_FRONTEND_APP_VERSION="frontend $COLOR - $VERSION"

    echo "deploying new revision of $WORKER_FRONTEND_APP_ID of $WORKER_FRONTEND_APP_VERSION" 

cat <<EOF > frontend.yaml
kind: containerapp
location: $LOCATION
name: $FRONTEND_APP_ID
resourceGroup: $RESOURCE_GROUP
type: Microsoft.App/containerApps
tags:
    app: frontend
    version: $WORKER_FRONTEND_APP_VERSION
    color: $COLOR
properties:
    managedEnvironmentId: /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/managedEnvironments/$CONTAINERAPPS_ENVIRONMENT_NAME
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
        dapr:
          enabled: true
          appPort: 8080
          appId: $FRONTEND_APP_ID
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
          - name: INSTRUMENTATIONKEY
            value: $AI_INSTRUMENTATION_KEY
          resources:
              cpu: 1
              memory: 2Gi
        scale:
          minReplicas: 1
          maxReplicas: 4
          rules:
          - name: frontendrule
            custom:
              type: http
              metadata:
                concurrentRequests: 10
EOF

    az containerapp update  -n $FRONTEND_APP_ID -g $RESOURCE_GROUP --yaml frontend.yaml

    az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "{FQDN:properties.configuration.ingress.fqdn,ProvisioningState:properties.provisioningState}" --out table

    echo "$BACKEND_APP_ID has the following revisions:"

    az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}" -o table

    NEW_FRONTEND_RELEASE_NAME=$(az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query 'reverse(sort_by([].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}[?Active!=`false`], &Created))| [0].Revision' -o tsv)

    WORKER_FRONTEND_REVISION_FQDN=$(az containerapp revision show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --revision $NEW_FRONTEND_RELEASE_NAME --query "properties.fqdn" -o tsv)

    echo "revision fqdn is $WORKER_FRONTEND_REVISION_FQDN"

    echo "here we can make a decision to abort and deactivate the new release"

    sleep 10

    RES_FRONTEND=$(curl --write-out "%{http_code}\n" -f -s $WORKER_FRONTEND_REVISION_FQDN/ping --output frontend.txt )
    echo $RES_FRONTEND

    if [ $RES_FRONTEND = "301" ]; then

        echo "frontend is up and running and responded with $RES_FRONTEND"
        
        echo "increasing traffic split to 0/100"
        az containerapp ingress traffic set --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=0 $NEW_FRONTEND_RELEASE_NAME=100
        sleep 5

        echo "deactivating $OLD_FRONTEND_RELEASE_NAME"
        az containerapp revision deactivate --name $FRONTEND_APP_ID -g $RESOURCE_GROUP --revision $OLD_FRONTEND_RELEASE_NAME 

        sleep 5

        az containerapp revision list -g $RESOURCE_GROUP -n $FRONTEND_APP_ID --query "[].{Revision:name,Replicas:properties.replicas,Active:properties.active,Created:properties.createdTime,FQDN:properties.fqdn}" -o table

        WORKER_FRONTEND_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP --name $FRONTEND_APP_ID --query "properties.configuration.ingress.fqdn" -o tsv)

    else
        echo "frontend responded with $RES_FRONTEND - deployment failed"

        echo "activating previous backend revison $OLD_BACKEND_RELEASE_NAME again"
        az containerapp revision activate --name $BACKEND_APP_ID -g $RESOURCE_GROUP --revision $OLD_BACKEND_RELEASE_NAME 
        
        sleep 5

        az containerapp ingress traffic set --name $BACKEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_BACKEND_RELEASE_NAME=100 latest=0

        sleep 5

        echo "deleting latest backend revision $NEW_BACKEND_RELEASE_NAME"
        az containerapp revision deactivate --name $BACKEND_APP_ID -g $RESOURCE_GROUP --revision $NEW_BACKEND_RELEASE_NAME 

        echo "bringing back the original frontend release $OLD_FRONTEND_RELEASE_NAME"
        az containerapp ingress traffic set --name $FRONTEND_APP_ID --resource-group $RESOURCE_GROUP --traffic-weight $OLD_FRONTEND_RELEASE_NAME=100 latest=0

        sleep 5

        echo "deleting latest frontend revision $NEW_FRONTEND_RELEASE_NAME again"
        az containerapp revision deactivate --name $FRONTEND_APP_ID -g $RESOURCE_GROUP --revision $NEW_FRONTEND_RELEASE_NAME 
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
