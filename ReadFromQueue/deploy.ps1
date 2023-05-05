$grp = "ReadFromQueueRG"
$loc = "westeurope"
$storageAccount = "readfromqueue20230505"
$queue = "myqueue"
$cne = "capps-env"

# creating resource group
az group create --name $grp `
    --location $loc

# azure storage queue configuration
az storage account create --name $storageAccount `
    --resource-group $grp `
    --location "$loc" `
    --sku Standard_LRS `
    --kind StorageV2
    
$queueConnectionString = (az storage account show-connection-string -g $grp --name $storageAccount `
        --query connectionString `
        --out json)

az storage queue create --name $queue `
    --account-name $storageAccount `
    --connection-string $queueConnectionString

#DefaultEndpointsProtocol=https;AccountName=readfromqueue20230505;AccountKey=dS2e0HcUBEYvWFb17e2MF+0HrZYyq9uW1HpbtHgDBdxvrs8lA3AzgmvnNR3Ur0J6DCmAUogdu0ku+AStrBSHwA==;BlobEndpoint=https://readfromqueue20230505.blob.core.windows.net/;TableEndpoint=https://readfromqueue20230505.table.core.windows.net/;QueueEndpoint=https://readfromqueue20230505.queue.core.windows.net/;FileEndpoint=https://readfromqueue20230505.file.core.windows.net/

for ($i = 1; $i -lt 10; $i++) {

    Write-Host "$i -> $queue"

    $message = "Queue Message - $i"

    $bytes = [System.Text.Encoding]::Unicode.GetBytes($message)
    $encoded =[Convert]::ToBase64String($bytes)

    az storage message put `
        --content $encoded `
        --queue-name $queue `
        --connection-string $queueConnectionString `
        --output none

}

$dContainer = "read-from-queue"
$dRegistry ="dragandanga"
# build image and push to Azure Container Registry
docker build -f ReadFromQueue\Dockerfile  --force-rm -t $dContainer .
docker tag $dContainer $dRegistry/$dContainer
docker push $dRegistry/$dContainer

$environment = "read-from-queue-env"
# creating environment
az containerapp env create --name $environment `
                           --resource-group $grp `
                           --internal-only false `
                           --location $loc

$contanerAppName ="read-from-queue"
# creating the Container App
az containerapp create `
  --name $contanerAppName `
  --resource-group $grp `
  --environment $environment `
  --image $dRegistry/$dContainer `
  --secrets "queue-connection-string=$queueConnectionString" `
  --env-vars "QueueName=$queue" "ConnectionString=secretref:queue-connection-string" `
  --min-replicas 0 `
  --max-replicas 5 `
  --scale-rule-name "azure-storage-queue-rule" `
  --scale-rule-type azure-queue `
  --scale-rule-metadata "queueName=$queue" `
                        "namespace=azure-queue" `
                        "queueLength=5" `
                        "activationQueueLength=5" `
                        "connectionFromEnv=secretref:queue-connection-string" `
                        "accountName=$storageAccount" `
                        "cloud=AzurePublicCloud" `
  --scale-rule-auth "connection=secretref:queue-connection-string" `

  1..100 | ForEach-Object -Parallel {
    $queue = $($using:queue)
    $queueConnectionString = $($using:queueConnectionString)

    Write-Host "$_ -> $queue"

    $message = "Queue Message X - $_"

    $bytes = [System.Text.Encoding]::Unicode.GetBytes($message)
    $encoded =[Convert]::ToBase64String($bytes)

    az storage message put `
        --content $encoded `
        --queue-name $queue `
        --connection-string $queueConnectionString `
        --output none

} -ThrottleLimit 10

