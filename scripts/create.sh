#!/bin/sh

#
# wget https://raw.githubusercontent.com/denniszielke/container_demos/master/scripts/deploy_wa.sh
# chmod +x ./deploy_wa.sh
# bash ./deploy_wa.sh
#

set -e

#az extension remove -n workerapp
#az extension add --source https://workerappscliextension.blob.core.windows.net/azure-cli-extension/workerapp-0.1.3-py2.py3-none-any.whl -y

# calculator properties
FRONTEND_APP_ID="calc-frontend"
BACKEND_APP_ID="http-calcback"
VERSION="1.8.19" # version tag showing up in app
COLOR="green" # color highlighting
LAGGY="true" # if true the backend will cause random delays
BUGGY="false" # if true the backend will randomly generate 500 errors

# infrastructure deployment properties
DEPLOYMENT_NAME="dzca11c" # here enter unique deployment name (ideally short and with letters for global uniqueness)
AZURE_CORE_ONLY_SHOW_ERRORS="True"
CONTAINERAPPS_ENVIRONMENT_NAME="$DEPLOYMENT_NAME-env" # Name of the ContainerApp Environment
LOG_ANALYTICS_WORKSPACE_NAME="$DEPLOYMENT_NAME-lg"
LOCATION="northcentralus" #"eastus2euap" #"westeurope" # here enter the datacenter location can be eastus or westeurope
CA_LOCATION="Central US EUAP"
RESOURCE_GROUP=$DEPLOYMENT_NAME # here enter the resources group
VNET_NAME="$DEPLOYMENT_NAME-vnet"
APPGW_SUBNET_NAME="gw-1-subnet"
APPS_SUBNET_NAME="apps-2-subnet" 
VAULT_NAME=akv1$KUBE_NAME
SECRET_NAME="mySecret"
SUBSCRIPTION_ID=$(az account show --query id -o tsv) # here enter your subscription id
TENANT_ID=$(az account show --query tenantId -o tsv)
MY_OWN_OBJECT_ID=$(az ad signed-in-user show --query objectId --output tsv) # this will be your own aad object id
az account set --subscription $SUBSCRIPTION_ID

if [ $(az group exists --name $RESOURCE_GROUP) = false ]; then
    echo "creating resource group $RESOURCE_GROUP..."
    az group create -n $RESOURCE_GROUP -l $LOCATION -o none
    echo "resource group $RESOURCE_GROUP created"
else   
    echo "resource group $RESOURCE_GROUP already exists"
fi

echo "setting up vnet"

VNET_RESOURCE_ID=$(az network vnet list -g $RESOURCE_GROUP --query "[?contains(name, '$VNET_NAME')].id" -o tsv)
if [ "$VNET_RESOURCE_ID" == "" ]; then
    echo "creating vnet $VNET_NAME..."
    az network vnet create  --address-prefixes "10.0.0.0/20"  -g $RESOURCE_GROUP -n $VNET_NAME -o none
    az network vnet subnet create -g $RESOURCE_GROUP --vnet-name $VNET_NAME -n $APPGW_SUBNET_NAME --address-prefix 10.0.2.0/24  -o none
    az network vnet subnet create -g $RESOURCE_GROUP --vnet-name $VNET_NAME -n $APPS_SUBNET_NAME --address-prefix 10.0.4.0/22  -o none
    VNET_RESOURCE_ID=$(az network vnet show -g $RESOURCE_GROUP -n $VNET_NAME --query id -o tsv)
    echo "created $VNET_RESOURCE_ID"
else
    echo "vnet $VNET_RESOURCE_ID already exists"
fi

APPS_SUBNET_ID=$(az network vnet subnet show -g $RESOURCE_GROUP --vnet-name $VNET_NAME -n $APPS_SUBNET_NAME --query id -o tsv)

# echo "creating service principals"
# az ad sp create --id a94933b8-d06a-4ee9-9240-fc5ff4584f8d
# az ad sp create --id bcad2cc5-28f9-4de2-8351-1ba20e241bd4

# echo "assigning permissions"
# az role assignment create --assignee a94933b8-d06a-4ee9-9240-fc5ff4584f8d --scope "/subscriptions/$SUBSCRIPTION_ID" --role "Network Contributor"
# az role assignment create --assignee bcad2cc5-28f9-4de2-8351-1ba20e241bd4 --scope $KUBE_POD_SUBNET_ID --role "Network Contributor"

echo "setting up azure monitor"

WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace list --resource-group $RESOURCE_GROUP --query "[?contains(name, '$LOG_ANALYTICS_WORKSPACE_NAME')].id" -o tsv)
if [ "$WORKSPACE_RESOURCE_ID" == "" ]; then
    echo "creating workspace $LOG_ANALYTICS_WORKSPACE_NAME in $RESOURCE_GROUP"
    az monitor log-analytics workspace create --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_WORKSPACE_NAME --location $LOCATION -o none
    WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace show --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_WORKSPACE_NAME -o json | jq '.id' -r)

    az monitor app-insights component create --app $LOG_ANALYTICS_WORKSPACE_NAME-ai --location $LOCATION --resource-group $RESOURCE_GROUP --application-type web --kind web --workspace $WORKSPACE_RESOURCE_ID
    
else
    echo "workspace $WORKSPACE_RESOURCE_ID already exists"
fi

# VAULT_ID=$(az keyvault list -g $RESOURCE_GROUP --query "[?contains(name, '$VAULT_NAME')].id" -o tsv)
# if [ "$VAULT_ID" == "" ]; then
#     echo "creating keyvault $VAULT_NAME"
#     az keyvault create -g $RESOURCE_GROUP -n $VAULT_NAME -l $LOCATION -o none
#     az keyvault secret set -n $SECRET_NAME --vault-name $VAULT_NAME --value MySuperSecretThatIDontWantToShareWithYou! -o none
#     VAULT_ID=$(az keyvault show -g $RESOURCE_GROUP -n $VAULT_NAME -o tsv --query id)
#     echo "created keyvault $VAULT_ID"
# else
#     echo "keyvault $VAULT_ID already exists"
#     VAULT_ID=$(az keyvault show -g $RESOURCE_GROUP -n $VAULT_NAME -o tsv --query name)
# fiGroupManagement.aspx?Group=squallinsiders&Operation=join

CONTAINER_APP_ENV_ID=$(az containerapp env list -g $RESOURCE_GROUP --query "[?contains(name, '$CONTAINERAPPS_ENVIRONMENT_NAME')].id" -o tsv)
if [ "$CONTAINER_APP_ENV_ID" == "" ]; then
    echo "creating worker app env $CONTAINER_APP_ENV_ID"

    AI_INSTRUMENTATION_KEY=$(az monitor app-insights component show --app $LOG_ANALYTICS_WORKSPACE_NAME-ai -g $RESOURCE_GROUP --query "[instrumentationKey]" -o tsv)
    LOG_ANALYTICS_WORKSPACE_CLIENT_ID=`az monitor log-analytics workspace show --query customerId -g $RESOURCE_GROUP -n $LOG_ANALYTICS_WORKSPACE_NAME -o tsv`
    LOG_ANALYTICS_WORKSPACE_CLIENT_SECRET=`az monitor log-analytics workspace get-shared-keys --query primarySharedKey -g $RESOURCE_GROUP -n $LOG_ANALYTICS_WORKSPACE_NAME -o tsv`
    echo "workspace id $LOG_ANALYTICS_WORKSPACE_CLIENT_ID"
    echo "secret $LOG_ANALYTICS_WORKSPACE_CLIENT_SECRET"
    echo "ai key $AI_INSTRUMENTATION_KEY"å

    az containerapp env create -n $CONTAINERAPPS_ENVIRONMENT_NAME -g $RESOURCE_GROUP --logs-workspace-id $LOG_ANALYTICS_WORKSPACE_CLIENT_ID --logs-workspace-key $LOG_ANALYTICS_WORKSPACE_CLIENT_SECRET --location "$CONTAINERAPPS_LOCATION" --instrumentation-key $AI_INSTRUMENTATION_KEY # --subnet-resource-id $KUBE_POD_SUBNET_ID

    CONTAINER_APP_ENV_ID=$(az containerapp env show -g $RESOURCE_GROUP -n $CONTAINERAPPS_ENVIRONMENT_NAME -o tsv --query id)
    echo "created app env $CONTAINER_APP_ENV_ID"
else
    echo "worker app env $CONTAINER_APP_ENV_ID already exists"
    AI_INSTRUMENTATION_KEY=$(az monitor app-insights component show --app $LOG_ANALYTICS_WORKSPACE_NAME-ai -g $RESOURCE_GROUP --query "[instrumentationKey]" -o tsv)
fi

WORKER_BACKEND_APP_ID=$(az containerapp list -g $RESOURCE_GROUP --query "[?contains(name, '$BACKEND_APP_ID')].id" -o tsv)
if [ "$WORKER_BACKEND_APP_ID" == "" ]; then
    #az containerapp delete -g $RESOURCE_GROUP --name $BACKEND_APP_ID -y

    WORKER_BACKEND_APP_VERSION="backend $COLOR - $VERSION"

    echo "creating worker app $BACKEND_APP_ID of $WORKER_BACKEND_APP_VERSION"

    # az group deployment create \
    #     --name $BACKEND_APP_ID \
    #     --resource-group $RESOURCE_GROUP \
    #     --template-file "wa/backend_template.json" \
    #     --parameters "environment_id=$CONTAINER_APP_ENV_ID" \
    #     --parameters "location=North Central US (Stage)" \
    #     --parameters "instrumentation_key=$AI_INSTRUMENTATION_KEY" \
    #     --parameters "version=backend blue - 1.0.2"

    az containerapp create -e $CONTAINERAPPS_ENVIRONMENT_NAME -g $RESOURCE_GROUP \
     -i denniszielke/js-calc-backend:latest \
     -n $BACKEND_APP_ID \
     --cpu 0.5 --memory 250Mi --enable-dapr false \
     -v "LAGGY=$LAGGY,BUGGY=$BUGGY,PORT=8080,VERSION=$WORKER_BACKEND_APP_VERSION,INSTRUMENTATIONKEY=$AI_INSTRUMENTATION_KEY" \
     --ingress external \
     --location "$CONTAINERAPPS_LOCATION" \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_BACKEND_APP_VERSION" \
     --target-port 8080

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
     -i denniszielke/js-calc-backend:latest \
     -n $BACKEND_APP_ID \
     --cpu 0.5 --memory 250Mi --enable-dapr false \
     -v "LAGGY=$LAGGY,BUGGY=$BUGGY,PORT=8080,VERSION=$WORKER_BACKEND_APP_VERSION,INSTRUMENTATIONKEY=$AI_INSTRUMENTATION_KEY" \
     --ingress external \
     --location "$CONTAINERAPPS_LOCATION" \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_BACKEND_APP_VERSION" \
     --target-port 8080  
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
if [ "$WORKER_FRONTEND_APP_ID" == "" ]; then
    #az containerapp delete -g $RESOURCE_GROUP --name $FRONTEND_APP_ID -y

    WORKER_FRONTEND_APP_VERSION="frontend $COLOR - $VERSION"

    echo "creating worker app $FRONTEND_APP_ID of $WORKER_FRONTEND_APP_VERSION using $WORKER_BACKEND_FQDN"

    az containerapp create -e $CONTAINERAPPS_ENVIRONMENT_NAME -g $RESOURCE_GROUP \
     -i denniszielke/js-calc-frontend:latest \
     -n $FRONTEND_APP_ID \
     --cpu 0.5 --memory 250Mi --enable-dapr false \
     -v "LAGGY=$LAGGY,BUGGY=$BUGGY,PORT=8080,VERSION=$WORKER_FRONTEND_APP_VERSION,INSTRUMENTATIONKEY=$AI_INSTRUMENTATION_KEY,ENDPOINT=$WORKER_BACKEND_FQDN" \
     --ingress external \
     --location "$CONTAINERAPPS_LOCATION" \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_FRONTEND_APP_VERSION" \
     --target-port 8080  

    # az group deployment create \
    #     --name $FRONTEND_APP_ID \
    #     --resource-group $RESOURCE_GROUP \
    #     --template-file "wa/frontend_template.json" \
    #     --parameters "environment_id=$CONTAINER_APP_ENV_ID" \
    #     --parameters "location=North Central US (Stage)" \
    #     --parameters "instrumentation_key=$AI_INSTRUMENTATION_KEY" \
    #     --parameters "backend_endpoint=$WORKER_BACKEND_FQDN"

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
     -i denniszielke/js-calc-frontend:latest \
     -n $FRONTEND_APP_ID \
     --cpu 0.5 --memory 250Mi --enable-dapr false \
     -v "LAGGY=$LAGGY,BUGGY=$BUGGY,PORT=8080,VERSION=$WORKER_FRONTEND_APP_VERSION,INSTRUMENTATIONKEY=$AI_INSTRUMENTATION_KEY,ENDPOINT=$WORKER_BACKEND_FQDN" \
     --ingress external \
     --location "$CONTAINERAPPS_LOCATION" \
     --max-replicas 10 --min-replicas 1 \
     --revisions-mode multiple \
     --tags "app=backend,version=$WORKER_FRONTEND_APP_VERSION" \
     --target-port 8080  

    #--scale-rules "wa/httpscaler.json" --debug --verbose

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

echo "creating application insights release annotation"
# https://docs.microsoft.com/en-us/azure/azure-monitor/app/annotations
ID=$(uuidgen)
ANNOTATIONNAME="release $VERSION"
EVENTTIME=$(date '+%Y-%m-%dT%H:%M:%S')  #$(printf '%(%Y-%m-%dT%H:%M:%S)T')
CATEGORY="Deployment"
RESOURCE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/microsoft.insights/components/$LOG_ANALYTICS_WORKSPACE_NAME-ai"

JSON_STRING=$( jq -n -c \
                  --arg id "$ID" \
                  --arg an "$ANNOTATIONNAME" \
                  --arg et "$EVENTTIME" \
                  --arg cg "$CATEGORY" \
                  '{Id: $id, AnnotationName: $an, EventTime: $et, Category: $cg}' ) 
                  
JSON_STRING=$(echo $JSON_STRING | tr '"' "'")
echo $JSON_STRING

az rest --method put --uri "$RESOURCE/Annotations?api-version=2015-05-01" --body "$JSON_STRING"
