$subscriptionId = 'yyy'
 $appInsightsResourceGroup = 'zzz'
 $appInsightsName = 'xxx-ai'
 
 $tables = @(
     'AppTraces'
 )
 
 foreach ($table in $tables) {

    
  New-AzOperationalInsightsPurgeWorkspace `
     -ResourceGroupName 'p-mgt-app' `
     -WorkspaceName 'p-mgt-app5f5blomy8-log': `
     -Table $table `
     -Column '_ResourceId' `
     -OperatorProperty '==' `
     -Value "/subscriptions/$subscriptionId/resourceGroups/$appInsightsResourceGroup/providers/Microsoft.Insights/components/$appInsightsName" `
     -Force

 }