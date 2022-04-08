# Blue green deployments on Azure Container Apps using GitHub Actions

This reposistory hosts the calculator sample application to demonstrate continuous blue/green application deployments using GitHub Action on Azure Container Apps.

In order to set up this demo you need to follow the instructions below.

This scenarios will make use of the following new features:
- Azure Container Apps as runtime for our containers
- Builtin Dapr for solving service-to-service invocation inside the cluster
- Builtin Keda for automatically scaling containers based on traffic
- Builtin Envoy for implementing traffic splits between releases
- Builtin Distributed Tracing in Application Insights
- GitHub Actions with Federated Service Identity support for Azure


![](/img/ghbgdepl.png)


## The calculator application
A couple of details on the application that is part of this scenario:
- The calculator application is multi service app written in Node that calculates prime factors for random numbers.
- The frontend application is making use of the dapr state store component to cache already calcualted results in an Azure Redis Cache instance.
- The backend application is beeing called by the frontend application via dapr service invocation to calculate the prime factors and return the results.
- The number of replicas of both frontend and backend Container App instances is beeing determined by the number of requests per second.
- All traces will be agregated using the dapr side cars in Application Insights

![](/img/caappsbg.png)

## Deployment of the Azure resources and GitHub configuration

### Set up workload Identity for your GitHub Actions to use federated trust

Official documentation:
https://docs.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation-create-trust-github?tabs=azure-portal

We will create a service principal and grant it permissions on a dedicated resource group

```
DEPLOYMENT_NAME="dzca15cgithub" # here the deployment
RESOURCE_GROUP=$DEPLOYMENT_NAME # here enter the resources group
LOCATION="northeurope" # azure region can only be canadacentral or northeurope
AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv) # here enter your subscription id
GHUSER="denniszielke" # replace with your user name
GHREPO="blue-green-with-containerapps" # here the repo name
AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
GHREPO_BRANCH=":ref:refs/heads/main"
az group create -n $RESOURCE_GROUP -l $LOCATION -o none

AZURE_CLIENT_ID=$(az ad sp create-for-rbac --name "$DEPLOYMENT_NAME" --role contributor --scopes "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" -o json | jq -r '.appId')

AZURE_CLIENT_OBJECT_ID="$(az ad app show --id ${AZURE_CLIENT_ID} --query objectId -o tsv)"

az rest --method POST --uri "https://graph.microsoft.com/beta/applications/$AZURE_CLIENT_OBJECT_ID/federatedIdentityCredentials" --body "{'name':'$DEPLOYMENT_NAME','issuer':'https://token.actions.githubusercontent.com','subject':'repo:$GHUSER/$GHREPO$GHREPO_BRANCH','description':'GitHub Actions for $DEPLOYMENT_NAME','audiences':['api://AzureADTokenExchange']}"

```
If the last step did not work, you need to grant your service principal the ability to issue a azure ad authentication token to your GitHub Action pipelines that are part of the main branch by going into Azure Active Directory -> App registrations -> YourApp -> Certificates & secrets -> Federated credentials.

![](/img/aadtrustserviceidentity.png)

Next you need to add the following secrets to your github repository:
- AZURE_CLIENT_ID
- AZURE_SUBSCRIPTION_ID
- AZURE_TENANT_ID
- RESOURCE_GROUP

![](/img/ghsecrets.png)

The nice thing about this is that you do NOT need to configure a client secret.

### Deployment of the azure resources

If the permission and the application registration are set up correctly you can trigger the deployment of the Azure resources by running the `deploy-infrastructure` workflow manually.

![](/img/wfresources.png)

### Triggering blue/green deployments

Once the infrastructure is deployed you can trigger a first deployment by changing any part of the `apps` or `scripts` folder contents.
By changing content again you can see the new version slowly beeing rolled out (after it has been validated) in the frontend container app user interface.
![](/img/bgcalculator.png)

The logic for the blue green deployment is implemented in the [deploy](https://github.com/denniszielke/blue-green-with-containerapps/blob/main/scripts/deploy.sh) script.

You can also see what is happening in Application Insights
![](/img/tracing.png)

## Contributing

This project welcomes contributions and suggestions.

