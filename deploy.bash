LOCATION=canadaeast
RESOURCE_GROUP='demo-openai-webapp-private'

az group create --location $LOCATION --resource-group $RESOURCE_GROUP

az deployment group create --template-file ./infra/main.bicep \
  --resource-group $RESOURCE_GROUP \
  --parameters @./infra/parameters.json  