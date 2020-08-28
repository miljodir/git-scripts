#Source storage account
$rgName ="roger02"
$location ="East Asia"
$storageAccountName ="roger1026"
$diskName ="rogerdisk"

#Target storage account
$destrgName ="roger01"
$destlocation ="West Europe"
$deststorageAccountName ="roger109"
$destdiskName ="destrogerdisk"
 
#Assign access to the source disk
$sas =Grant-AzureRmDiskAccess -ResourceGroupName $rgName -DiskName $diskName -DurationInSecond 3600 -Access Read

$saKey =Get-AzureRmStorageAccountKey -ResourceGroupName $destrgName -Name $deststorageAccountName
$storageContext =New-AzureStorageContext –StorageAccountName $deststorageAccountName -StorageAccountKey $saKey[0].Value
New-AzureStorageContainer -Context $storageContext -Name vhds10261

Start-AzureStorageBlobCopy -AbsoluteUri $sas.AccessSAS -DestContainer vhds10261 -DestContext $storageContext -DestBlob $destdiskName

Get-AzureStorageBlobCopyState -Context $storageContext -Blob $destdiskName -Container vhds10261