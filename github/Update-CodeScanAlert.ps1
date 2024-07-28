<#
.SYNOPSIS
Dismiss a specific code scanning alert across all repositories in an org
#>

param (
  [string] [Parameter(Mandatory=$false)] $org = "miljodir",
  [string] [Parameter(Mandatory=$false)] $tool = "terrascan"
)

$ids = @(
"CKV_GIT_5",
"CKV2_AZURE_1",
"CKV2_AZURE_18",
"CKV2_AZURE_21",
"CKV_AZURE_17",
"CKV_AZURE_23",
"CKV_AZURE_24",
"CKV_AZURE_33",
"CKV_AZURE_41",
"CKV_AZURE_63",
"CKV_AZURE_65",
"CKV_AZURE_66",
"CKV_AZURE_88",
"CKV_AZURE_109",
"CKV_AZURE_114",
"CKV_AZURE_182",
"CKV_AZURE_183",
"CKV_AZURE_16",
"CKV2_AZURE_10",
"CKV2_AZURE_12",
"CKV_AZURE_13",
"CKV_AZURE_50",
"CKV_AZURE_211",
"CKV_AZURE_212",
"CKV_AZURE_225",
"CKV_TF_1",
"CKV_TF_2",
"CKV2_GHA_1",
"CKV2_K8S_6",
"CKV_GHA_7"
)

$alerts = gh api --method GET "/orgs/$org/code-scanning/alerts?state=open" --paginate | ConvertFrom-Json

    foreach ($alert in $alerts)
    {

        if ( $alert.most_recent_instance.location.path -like "*-values.yaml")
        {
            gh api --method PATCH "/repos/$org/$($alert.repository.name)/code-scanning/alerts/$($alert.number)" -f "state=dismissed" -f "dismissed_reason=false positive" -f "dismissed_comment=The alert detected a potential misconfig in the -values.yaml file, which only contains overrides and cannot be evaulated by itself"
        }
        elseif ($alert.rule.id -in $ids)
        {
            gh api --method PATCH "/repos/$org/$($alert.repository.name)/code-scanning/alerts/$($alert.number)" -f "state=dismissed" -f "dismissed_reason=false positive" -f "dismissed_comment=This alert is deemed not relevant by the MAP team, is a false positive, or is covered by other measures"
        }
    }

