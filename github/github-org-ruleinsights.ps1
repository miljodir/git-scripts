<#
.SYNOPSIS
    Finds failed ruleset evaluations for the past month (maximum) in a GitHub organization and filters for specific rules.
#>

param (
    [string] [Parameter(Mandatory=$false)] $org = "miljodir",
    [string] [Parameter(Mandatory=$false)] $timeperiod = "month",
    [string] [Parameter(Mandatory=$false)] $result = "fail",
    [string[]] [Parameter(Mandatory=$false)] $filter = @("global-restricted-paths", "global-secret-files")
)

$failures = gh api "/orgs/$org/rulesets/rule-suites?time_period=$timeperiod&rule_suite_result=$result" --paginate | ConvertFrom-Json

$hits = @()

foreach ($failure in $failures) {
    Write-Host "Checking failed suite: $($failure.id) pushed at $($suite.pushed_at)"
    $suite = gh api "/orgs/$org/rulesets/rule-suites/$($failure.id)" | ConvertFrom-Json

    foreach ($rule in $suite.rule_evaluations) {
        if ($rule.rule_source.name -eq $filter[0] -or $rule.rule_source.name -eq $filter[1] -and $rule.result -eq $result) {
            Write-Host "Found a hit for user $($suite.actor_name) at $($suite.pushed_at) in repo $($failure.repository_name) who triggered rule $($rule.rule_source.name) with details: $($rule.details)" -ForegroundColor Red

            $script:hits += [PSCustomObject]@{
                Actor   = $($suite.actor_name)
                Pushed  = $($suite.pushed_at)
                Repo    = $($failure.repository_name)
                Rule    = $($rule.rule_source.name)
                Details = $($rule.details)
                Result  = $($rule.result)
            }
            
        }
    }
}

$hits | Format-Table
