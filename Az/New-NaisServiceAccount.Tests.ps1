BeforeAll {
    $script:saScript = Join-Path $PSScriptRoot 'New-NaisServiceAccount.ps1'
    $script:previousPath = $env:PATH
    $script:previousScenario = $env:SA_TEST_SCENARIO
    $script:previousLog = $env:SA_TEST_LOG
    $script:previousToken = $env:NAIS_API_TOKEN
    $stubDir = Join-Path $TestDrive 'stub'
    New-Item -ItemType Directory -Path $stubDir | Out-Null
    $source = @'
using System;
using System.IO;
using System.Net;
using System.Text;
using System.Text.Json.Nodes;

public class Stub {
    static string Log => Environment.GetEnvironmentVariable("SA_TEST_LOG");
    static string Scenario => Environment.GetEnvironmentVariable("SA_TEST_SCENARIO");

    static string Handle(string query, JsonNode variables) {
        if (query.Contains("isAdmin")) {
            return "{\"data\":{\"me\":{\"email\":\"admin@example.com\",\"isAdmin\":" + (Scenario == "not-admin" ? "false" : "true") + "}}}";
        }
        if (query.Contains("serviceAccounts(")) {
            string nodes = Scenario == "existing"
                ? "{\"id\":\"SA_team\",\"name\":\"team-provisioner\",\"team\":{\"slug\":\"other\"},\"roles\":{\"nodes\":[]}},"
                  + "{\"id\":\"SA_existing\",\"name\":\"team-provisioner\",\"team\":null,\"roles\":{\"nodes\":[{\"name\":\"Team creator\"}]}}"
                : "{\"id\":\"SA_other\",\"name\":\"something-else\",\"team\":null,\"roles\":{\"nodes\":[]}}";
            return "{\"data\":{\"serviceAccounts\":{\"nodes\":[" + nodes + "],\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null}}}}";
        }
        if (query.Contains("createServiceAccountToken")) {
            return "{\"data\":{\"createServiceAccountToken\":{\"secret\":\"s3cret-value\",\"serviceAccountToken\":{\"name\":\"t\",\"expiresAt\":\"" + variables["input"]["expiresAt"].GetValue<string>() + "\"}}}}";
        }
        if (query.Contains("createServiceAccount")) {
            return "{\"data\":{\"createServiceAccount\":{\"serviceAccount\":{\"id\":\"SA_new\",\"name\":\"" + variables["input"]["name"].GetValue<string>() + "\"}}}}";
        }
        if (query.Contains("assignRoleToServiceAccount")) {
            return "{\"data\":{\"assignRoleToServiceAccount\":{\"serviceAccount\":{\"id\":\"" + variables["input"]["serviceAccountID"].GetValue<string>() + "\"}}}}";
        }
        return "{\"data\":{\"me\":{\"email\":\"admin@example.com\"}}}";
    }

    public static int Main(string[] args) {
        if (string.Join(" ", args).StartsWith("api proxy --listen ")) {
            var listener = new HttpListener();
            listener.Prefixes.Add("http://" + args[3] + "/");
            listener.Start();
            while (true) {
                var context = listener.GetContext();
                string body = new StreamReader(context.Request.InputStream).ReadToEnd();
                File.AppendAllText(Log, body + Environment.NewLine);
                var request = JsonNode.Parse(body);
                byte[] bytes = Encoding.UTF8.GetBytes(Handle(request["query"].GetValue<string>(), request["variables"]));
                context.Response.ContentType = "application/json";
                context.Response.OutputStream.Write(bytes, 0, bytes.Length);
                context.Response.Close();
            }
        }
        return 3;
    }
}
'@
    Set-Content (Join-Path $stubDir 'Stub.cs') $source
    Set-Content (Join-Path $stubDir 'Stub.csproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework><RollForward>Major</RollForward></PropertyGroup></Project>'
    & dotnet build (Join-Path $stubDir 'Stub.csproj') -o (Join-Path $stubDir 'out') --nologo --verbosity quiet
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to build the CLI fixture.'
    }
    Copy-Item (Join-Path $stubDir 'out\Stub.dll') (Join-Path $TestDrive 'Stub.dll')
    Copy-Item (Join-Path $stubDir 'out\Stub.runtimeconfig.json') (Join-Path $TestDrive 'Stub.runtimeconfig.json')
    Copy-Item (Join-Path $stubDir 'out\Stub.exe') (Join-Path $TestDrive 'nais.exe')
    $env:PATH = "$TestDrive;$env:PATH"
    $env:SA_TEST_LOG = Join-Path $TestDrive 'requests.log'

    function Get-Mutations {
        Get-Content $env:SA_TEST_LOG | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.query -like 'mutation*' }
    }
}

AfterAll {
    $env:PATH = $script:previousPath
    $env:SA_TEST_SCENARIO = $script:previousScenario
    $env:SA_TEST_LOG = $script:previousLog
    $env:NAIS_API_TOKEN = $script:previousToken
}

Describe 'New-NaisServiceAccount' {
    BeforeEach {
        $env:SA_TEST_SCENARIO = 'new'
        $env:NAIS_API_TOKEN = $null
        Set-Content $env:SA_TEST_LOG ''
    }

    It 'creates a global service account with both roles and an expiring token without printing the secret' {
        $output = & $script:saScript -TokenExpiresInDays 30 6>&1 | Out-String
        $mutations = @(Get-Mutations)
        $create = @($mutations | Where-Object query -Match 'createServiceAccount\(')
        $create.Count | Should -Be 1
        $create[0].variables.input.name | Should -Be 'team-provisioner'
        $create[0].variables.input.PSObject.Properties.Name | Should -Not -Contain 'teamSlug'
        @($mutations | Where-Object query -Match 'assignRoleToServiceAccount' | ForEach-Object { "$($_.variables.input.serviceAccountID)/$($_.variables.input.roleName)" }) |
            Should -Be @('SA_new/Team creator', 'SA_new/Team owner')
        $token = @($mutations | Where-Object query -Match 'createServiceAccountToken')
        $token.Count | Should -Be 1
        $token[0].variables.input.serviceAccountID | Should -Be 'SA_new'
        $token[0].variables.input.expiresAt | Should -Be ([DateTime]::UtcNow.Date.AddDays(30).ToString('yyyy-MM-dd'))
        $env:NAIS_API_TOKEN | Should -Be 's3cret-value'
        $output | Should -Not -Match 's3cret-value'
    }

    It 'reuses an existing global service account and only assigns missing roles' {
        $env:SA_TEST_SCENARIO = 'existing'
        & $script:saScript 6>$null
        $mutations = @(Get-Mutations)
        @($mutations | Where-Object query -Match 'createServiceAccount\(').Count | Should -Be 0
        @($mutations | Where-Object query -Match 'assignRoleToServiceAccount' | ForEach-Object { "$($_.variables.input.serviceAccountID)/$($_.variables.input.roleName)" }) |
            Should -Be @('SA_existing/Team owner')
        @($mutations | Where-Object query -Match 'createServiceAccountToken')[0].variables.input.serviceAccountID | Should -Be 'SA_existing'
    }

    It 'refuses to run for users that are not Nais admins' {
        $env:SA_TEST_SCENARIO = 'not-admin'
        { & $script:saScript 6>$null } | Should -Throw '*not a Nais admin*'
        @(Get-Mutations).Count | Should -Be 0
    }

    It 'makes no changes with -WhatIf' {
        & $script:saScript -WhatIf 6>$null
        @(Get-Mutations).Count | Should -Be 0
        $env:NAIS_API_TOKEN | Should -BeNullOrEmpty
    }
}
