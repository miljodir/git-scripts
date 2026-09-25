BeforeAll {
    $script:importScript = Join-Path $PSScriptRoot 'Import-KeyVaultSecrets.ps1'
    $script:previousPath = $env:PATH
    $script:previousScenario = $env:IMPORT_TEST_SCENARIO
    $script:previousLog = $env:IMPORT_TEST_LOG
    $stubDir = Join-Path $TestDrive 'stub'
    New-Item -ItemType Directory -Path $stubDir | Out-Null
    $source = @'
using System;
using System.IO;
using System.Linq;
using System.Text.Json;

public class Stub {
    public static int Main(string[] args) {
        string program = Path.GetFileNameWithoutExtension(Environment.ProcessPath);
        File.AppendAllText(Environment.GetEnvironmentVariable("IMPORT_TEST_LOG"),
            program + " " + string.Join(" ", args) + Environment.NewLine);
        string operation = string.Join(" ", args.Take(3));
        string Get(string flag) => args[Array.IndexOf(args, flag) + 1];
        string scenario = Environment.GetEnvironmentVariable("IMPORT_TEST_SCENARIO");
        if (program == "az") {
            string subscription = Get("--subscription");
            if (operation.StartsWith("keyvault list ")) {
                string[] vaults = subscription == "d-tstsp1"
                    ? new[] { scenario == "short-suffix" ? "d-tstsp1abcd-kv" : "d-tstsp1abc123-kv" }
                    : subscription == "p-tstsp1"
                        ? new[] { "p-tstsp1-kv" }
                    : subscription == "d-tstsp3"
                        ? new[] { "d-othername-kv" }
                        : scenario == "conventional"
                            ? new[] { "d-tstsp2-service1", "d-tstsp2-service2-kv" }
                        : scenario == "target-collision"
                            ? new[] { "d-tstsp2-service1", "d-ts-service1" }
                            : new[] { "d-ts-service1", "d-ts-service2" };
                Console.WriteLine(JsonSerializer.Serialize(vaults));
            } else if (operation == "keyvault secret list") {
                string vault = Get("--vault-name");
                string[] names = scenario == "key-collision" ? new[] { "Shared--Key" }
                    : scenario == "empty" ? Array.Empty<string>()
                    : scenario == "hierarchy" || scenario == "existing-hierarchy"
                        ? new[] { "Service--Connection--String", "Sentry--Dsn", "PlainKey" }
                    : vault.Contains("service2") ? new[] { "Service2Key" }
                    : vault.Contains("service1") ? new[] { "Service1Key" }
                    : new[] { "DefaultKey" };
                Console.WriteLine(JsonSerializer.Serialize(names));
            } else if (operation == "keyvault secret show") {
                Console.WriteLine(JsonSerializer.Serialize(new { value = "value-" + Get("--name") }));
            } else {
                return 3;
            }
        } else if (program == "nais") {
            if (operation.StartsWith("secret list ")) {
                Console.WriteLine(scenario == "existing" || scenario == "existing-hierarchy"
                    ? JsonSerializer.Serialize(new[] { new { Name = "tstsp1-secrets" } }) : "[]");
            } else if (operation.StartsWith("secret get ")) {
                Console.WriteLine(scenario == "existing" || scenario == "existing-hierarchy"
                    ? JsonSerializer.Serialize(new { name = args[2], data = new[] { new { key = scenario == "existing" ? "DefaultKey" : "Service__Connection__String" } } })
                    : JsonSerializer.Serialize(new { name = args[2], data = Array.Empty<object>() }));
            } else if (operation.StartsWith("secret create ")) {
                Console.WriteLine("created");
            } else if (operation.StartsWith("secret set ")) {
                if (!args.Contains("--value-from-stdin") || args.Contains("--value")
                    || Console.In.ReadToEnd() != "value-" + Get("--key").Replace("__", "--")) {
                    return 4;
                }
                Console.WriteLine("set");
            } else {
                return 3;
            }
        } else {
            return 3;
        }
        return 0;
    }
}
'@
    Set-Content (Join-Path $stubDir 'Stub.cs') $source
    Set-Content (Join-Path $stubDir 'Stub.csproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>'
    & dotnet build (Join-Path $stubDir 'Stub.csproj') -o (Join-Path $stubDir 'out') --nologo --verbosity quiet
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to build the CLI fixtures.'
    }
    Copy-Item (Join-Path $stubDir 'out\Stub.dll') (Join-Path $TestDrive 'Stub.dll')
    Copy-Item (Join-Path $stubDir 'out\Stub.runtimeconfig.json') (Join-Path $TestDrive 'Stub.runtimeconfig.json')
    foreach ($command in @('az', 'nais')) {
        Copy-Item (Join-Path $stubDir 'out\Stub.exe') (Join-Path $TestDrive "$command.exe")
    }
    $env:PATH = "$TestDrive;$env:PATH"
    $env:IMPORT_TEST_LOG = Join-Path $TestDrive 'calls.log'
}

AfterAll {
    $env:PATH = $script:previousPath
    $env:IMPORT_TEST_SCENARIO = $script:previousScenario
    $env:IMPORT_TEST_LOG = $script:previousLog
}

Describe 'Import-KeyVaultSecrets' {
    BeforeEach {
        $env:IMPORT_TEST_SCENARIO = 'normal'
        Set-Content $env:IMPORT_TEST_LOG ''
    }

    It 'routes autogenerated and service vaults to the correct team and environment' {
        & $script:importScript -Subscriptions d-tstsp1, d-tstsp2, p-tstsp1
        $calls = Get-Content $env:IMPORT_TEST_LOG
        $calls | Should -Contain 'nais secret create tstsp1-secrets --team tstsp1 --environment dev'
        $calls | Should -Contain 'nais secret create tstsp1-secrets --team tstsp1 --environment prod'
        $calls | Should -Contain 'nais secret create tstsp2-service1-secrets --team tstsp2 --environment dev'
        $calls | Should -Contain 'nais secret create tstsp2-service2-secrets --team tstsp2 --environment dev'
        @($calls | Where-Object { $_ -like 'nais secret set *' }).Count | Should -Be 4
        $calls | Should -Contain 'az keyvault list --subscription d-tstsp2 --query [].name --output json'
        $calls | Should -Contain 'az keyvault secret show --vault-name d-ts-service2 --subscription d-tstsp2 --name Service2Key --output json'
        ($calls -join "`n") | Should -Not -Match 'value-DefaultKey|value-Service1Key|value-Service2Key'
    }

    It 'derives service names from conventional subscription-prefixed vaults' {
        $env:IMPORT_TEST_SCENARIO = 'conventional'
        & $script:importScript -Subscriptions d-tstsp2
        $calls = Get-Content $env:IMPORT_TEST_LOG
        $calls | Should -Contain 'nais secret create tstsp2-service1-secrets --team tstsp2 --environment dev'
        $calls | Should -Contain 'nais secret create tstsp2-service2-secrets --team tstsp2 --environment dev'
    }

    It 'never uses the -kv suffix as a service name' {
        & $script:importScript -Subscriptions d-tstsp3 3>$null
        $calls = Get-Content $env:IMPORT_TEST_LOG
        @($calls | Where-Object { $_ -like 'nais secret create *' }) | Should -Be @('nais secret create tstsp3-secrets --team tstsp3 --environment dev')
    }

    It 'merges distinct keys into a single secret per subscription' {
        & $script:importScript -Subscriptions d-tstsp2 -MergeVaults
        $calls = Get-Content $env:IMPORT_TEST_LOG
        @($calls | Where-Object { $_ -like 'nais secret create *' }) | Should -Be @('nais secret create tstsp2-secrets --team tstsp2 --environment dev')
        @($calls | Where-Object { $_ -like 'nais secret set *' }).Count | Should -Be 2
    }

    It 'allows an explicit full vault name instead of the derived name' {
        & $script:importScript -Subscriptions d-tstsp1 -IncludeVaultName
        Get-Content $env:IMPORT_TEST_LOG | Should -Contain 'nais secret create d-tstsp1abc123-kv-secrets --team tstsp1 --environment dev'
    }

    It 'ignores generated suffixes of different lengths' {
        $env:IMPORT_TEST_SCENARIO = 'short-suffix'
        & $script:importScript -Subscriptions d-tstsp1
        Get-Content $env:IMPORT_TEST_LOG | Should -Contain 'nais secret create tstsp1-secrets --team tstsp1 --environment dev'
    }

    It 'only imports requested names present in a vault' {
        & $script:importScript -Subscriptions d-tstsp2 -Names Service2Key
        $calls = Get-Content $env:IMPORT_TEST_LOG
        $calls | Should -Contain 'nais secret create tstsp2-service2-secrets --team tstsp2 --environment dev'
        @($calls | Where-Object { $_ -like 'nais secret set *' }).Count | Should -Be 1
    }

    It 'replaces every hierarchy separator in Nais keys but preserves Azure lookup names and plain keys' {
        $env:IMPORT_TEST_SCENARIO = 'hierarchy'
        & $script:importScript -Subscriptions d-tstsp1
        $calls = Get-Content $env:IMPORT_TEST_LOG
        $calls | Should -Contain 'az keyvault secret show --vault-name d-tstsp1abc123-kv --subscription d-tstsp1 --name Service--Connection--String --output json'
        $calls | Should -Contain 'nais secret set tstsp1-secrets --team tstsp1 --environment dev --key Service__Connection__String --value-from-stdin'
        $calls | Should -Contain 'nais secret set tstsp1-secrets --team tstsp1 --environment dev --key Sentry__Dsn --value-from-stdin'
        $calls | Should -Contain 'nais secret set tstsp1-secrets --team tstsp1 --environment dev --key PlainKey --value-from-stdin'
        ($calls -join "`n") | Should -Not -Match 'nais secret set .*--key .*--.*--value-from-stdin'
    }

    It 'filters by original Azure key name and writes the translated Nais key' {
        $env:IMPORT_TEST_SCENARIO = 'hierarchy'
        & $script:importScript -Subscriptions d-tstsp1 -Names 'Service--Connection--String'
        $calls = Get-Content $env:IMPORT_TEST_LOG
        @($calls | Where-Object { $_ -like 'nais secret set *' }) | Should -Be @('nais secret set tstsp1-secrets --team tstsp1 --environment dev --key Service__Connection__String --value-from-stdin')
    }

    It 'rejects a missing requested name before writing' {
        { & $script:importScript -Subscriptions d-tstsp2 -Names MissingKey } | Should -Throw '*Requested secret*'
        @(Get-Content $env:IMPORT_TEST_LOG | Where-Object { $_ -like 'nais *' }).Count | Should -Be 0
    }

    It 'rejects duplicate target names before writing' {
        $env:IMPORT_TEST_SCENARIO = 'target-collision'
        { & $script:importScript -Subscriptions d-tstsp2 } | Should -Throw '*More than one vault maps*'
        @(Get-Content $env:IMPORT_TEST_LOG | Where-Object { $_ -like 'nais *' }).Count | Should -Be 0
    }

    It 'rejects duplicate keys during merge before writing' {
        $env:IMPORT_TEST_SCENARIO = 'key-collision'
        { & $script:importScript -Subscriptions d-tstsp2 -MergeVaults } | Should -Throw '*already mapped*'
        @(Get-Content $env:IMPORT_TEST_LOG | Where-Object { $_ -like 'nais *' }).Count | Should -Be 0
    }

    It 'skips empty vaults without creating a secret' {
        $env:IMPORT_TEST_SCENARIO = 'empty'
        & $script:importScript -Subscriptions d-tstsp1
        @(Get-Content $env:IMPORT_TEST_LOG | Where-Object { $_ -like 'nais *' }).Count | Should -Be 0
    }

    It 'updates an existing key without recreating its secret' {
        $env:IMPORT_TEST_SCENARIO = 'existing'
        $warnings = @(& $script:importScript -Subscriptions d-tstsp1 3>&1)
        $calls = Get-Content $env:IMPORT_TEST_LOG
        @($calls | Where-Object { $_ -like 'nais secret create *' }).Count | Should -Be 0
        @($calls | Where-Object { $_ -like 'nais secret set *' }).Count | Should -Be 1
        ($warnings -join ' ') | Should -Match "Key 'DefaultKey' already exists"
    }

    It 'warns using the translated key when updating an existing hierarchical key' {
        $env:IMPORT_TEST_SCENARIO = 'existing-hierarchy'
        $warnings = @(& $script:importScript -Subscriptions d-tstsp1 3>&1)
        ($warnings -join ' ') | Should -Match "Key 'Service__Connection__String' already exists"
        Get-Content $env:IMPORT_TEST_LOG | Should -Contain 'nais secret set tstsp1-secrets --team tstsp1 --environment dev --key Service__Connection__String --value-from-stdin'
    }
}
