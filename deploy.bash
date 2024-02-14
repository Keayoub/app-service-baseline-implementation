LOCATION=location
RESOURCE_GROUP='Resource-Group-Name'
NAME_OF_WEB_APP='Name-of-web-app'

az group create --location $LOCATION --resource-group $RESOURCE_GROUP

az deployment group create --template-file ./infra/main.bicep \
  --resource-group $RESOURCE_GROUP \
  --parameters @./infra/parameters.json  

# deploy web app you need to be in the same network as the web app
# curl https://raw.githubusercontent.com/Azure-Samples/app-service-sample-workload/main/website/SimpleWebApp.zip -o SimpleWebApp.zip
# az webapp deployment source config-zip --resource-group $RESOURCE_GROUP --name $NAME_OF_WEB_APP --src SimpleWebApp.zip

# delete resource group
#az group delete --name $RESOURCE_GROUP