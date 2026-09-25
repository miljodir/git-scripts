BeforeAll {
    $script:teamScript = Join-Path $PSScriptRoot 'New-NaisTeams.ps1'
    $script:previousPath = $env:PATH
    $script:previousScenario = $env:TEAMS_TEST_SCENARIO
    $script:previousLog = $env:TEAMS_TEST_LOG
    $script:previousToken = $env:NAIS_API_TOKEN
    $stubDir = Join-Path $TestDrive 'stub'
    New-Item -ItemType Directory -Path $stubDir | Out-Null
    $source = @'
using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

public class Stub {
    static string Log => Environment.GetEnvironmentVariable("TEAMS_TEST_LOG");
    static string Scenario => Environment.GetEnvironmentVariable("TEAMS_TEST_SCENARIO");
    static readonly object LogLock = new object();

    static void Append(string line) {
        lock (LogLock) {
            for (int i = 0; ; i++) {
                try { File.AppendAllText(Log, line + Environment.NewLine); return; }
                catch (IOException) when (i < 20) { System.Threading.Thread.Sleep(50); }
            }
        }
    }

    static object User(string mail, string upn) => new Json.User { odataType = "#microsoft.graph.user", displayName = upn, mail = mail, userPrincipalName = upn };

    static string Members(params string[] emails) =>
        "{\"data\":{\"team\":{\"members\":{\"nodes\":[" + string.Join(",", emails.Select(e => "{\"user\":{\"email\":\"" + e + "\"}}")) + "],\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null}}}}}";

    static (int, string) Handle(string body, string auth) {
        if (Scenario == "require-token" && auth != "Bearer test-token") {
            return (401, "{\"errors\":[{\"message\":\"unauthorized\"}]}");
        }
        var request = JsonNode.Parse(body);
        string query = request["query"].GetValue<string>();
        var variables = request["variables"];
        if (query.Contains("createTeam")) {
            return (200, "{\"data\":{\"createTeam\":{\"team\":{\"slug\":\"" + variables["input"]["slug"].GetValue<string>() + "\"}}}}");
        }
        if (query.Contains("addTeamMember")) {
            return variables["input"]["userEmail"].GetValue<string>() == "unknown@example.com"
                ? (200, "{\"data\":null,\"errors\":[{\"message\":\"user not found\"}]}")
                : (200, "{\"data\":{\"addTeamMember\":{\"member\":{\"role\":\"MEMBER\"}}}}");
        }
        if (query.Contains("members(")) {
            return (200, variables["slug"].GetValue<string>() == "tstsp2"
                ? Members("dave@example.com")
                : Members("runner@example.com", "alice@example.com"));
        }
        if (query.Contains("teams(")) {
            return (200, variables["after"] == null
                ? "{\"data\":{\"teams\":{\"nodes\":[{\"slug\":\"other\"}],\"pageInfo\":{\"hasNextPage\":true,\"endCursor\":\"c1\"}}}}"
                : "{\"data\":{\"teams\":{\"nodes\":[{\"slug\":\"tstsp2\"}],\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":\"c2\"}}}}");
        }
        return (200, "{\"data\":{\"me\":{\"email\":\"runner@example.com\"}}}");
    }

    public static int Main(string[] args) {
        string program = Path.GetFileNameWithoutExtension(Environment.ProcessPath);
        Append(program + " " + string.Join(" ", args));
        string Get(string flag) => args[Array.IndexOf(args, flag) + 1];
        string joined = string.Join(" ", args);
        if (program == "az" && joined.StartsWith("ad group member list ")) {
            string group = Get("--group");
            object[] members = group == "az rbac sub d-tstsp1 contributors"
                ? new object[] {
                    User("alice.mail@example.com", "Alice@Example.com"),
                    User("bob.mail@example.com", "bob@example.com"),
                    new Json.User { odataType = "#microsoft.graph.group", displayName = "nested" } }
                : group == "az rbac sub p-tstsp1 contributors"
                    ? new object[] { User("alice@example.com", "alice@example.com"), User(null, "carol@example.com") }
                : group == "az rbac sub d-tstsp2 contributors"
                    ? new object[] { User("dave@example.com", "dave@example.com"), User("unknown@example.com", "unknown@example.com") }
                    : null;
            if (members == null) {
                Console.Error.WriteLine("Resource '" + group + "' does not exist.");
                return 1;
            }
            Console.WriteLine(JsonSerializer.Serialize(members));
            return 0;
        }
        if (program == "nais" && joined.StartsWith("api proxy --listen ")) {
            if (Scenario == "not-logged-in") {
                Console.Error.WriteLine("not logged in");
                return 1;
            }
            var listener = new HttpListener();
            listener.Prefixes.Add("http://" + Get("--listen") + "/");
            listener.Start();
            while (true) {
                var context = listener.GetContext();
                string body = new StreamReader(context.Request.InputStream).ReadToEnd();
                string auth = context.Request.Headers["Authorization"] ?? "none";
                Append("graphql auth=" + auth + " " + body);
                var (status, response) = Handle(body, auth);
                byte[] bytes = Encoding.UTF8.GetBytes(response);
                context.Response.StatusCode = status;
                context.Response.ContentType = "application/json";
                context.Response.OutputStream.Write(bytes, 0, bytes.Length);
                context.Response.Close();
            }
        }
        return 3;
    }
}

namespace Json {
    public class User {
        [System.Text.Json.Serialization.JsonPropertyName("@odata.type")]
        public string odataType { get; set; }
        public string displayName { get; set; }
        public string mail { get; set; }
        public string userPrincipalName { get; set; }
    }
}
'@
    Set-Content (Join-Path $stubDir 'Stub.cs') $source
    Set-Content (Join-Path $stubDir 'Stub.csproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework><RollForward>Major</RollForward></PropertyGroup></Project>'
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
    $env:TEAMS_TEST_LOG = Join-Path $TestDrive 'calls.log'

    function Get-GraphqlRequests {
        Get-Content $env:TEAMS_TEST_LOG | Where-Object { $_ -like 'graphql *' } | ForEach-Object {
            if ($_ -match '^graphql auth=(.*?) (\{.*)$') {
                $request = $Matches[2] | ConvertFrom-Json
                [pscustomobject]@{ Auth = $Matches[1]; Query = $request.query; Variables = $request.variables }
            }
        }
    }

    function Get-AddedMembers {
        Get-GraphqlRequests | Where-Object Query -Match 'addTeamMember' | ForEach-Object {
            "$($_.Variables.input.teamSlug)/$($_.Variables.input.userEmail)/$($_.Variables.input.role)"
        }
    }
}

AfterAll {
    $env:PATH = $script:previousPath
    $env:TEAMS_TEST_SCENARIO = $script:previousScenario
    $env:TEAMS_TEST_LOG = $script:previousLog
    $env:NAIS_API_TOKEN = $script:previousToken
}

Describe 'New-NaisTeams' {
    BeforeEach {
        $env:TEAMS_TEST_SCENARIO = 'normal'
        $env:NAIS_API_TOKEN = $null
        Set-Content $env:TEAMS_TEST_LOG ''
    }

    It 'creates a missing team once and adds the union of dev and prod group members by userPrincipalName' {
        & $script:teamScript -Subscriptions d-tstsp1, p-tstsp1 3>$null
        $calls = Get-Content $env:TEAMS_TEST_LOG
        $calls | Should -Contain 'az ad group member list --group az rbac sub d-tstsp1 contributors --output json'
        $calls | Should -Contain 'az ad group member list --group az rbac sub p-tstsp1 contributors --output json'
        $creates = @(Get-GraphqlRequests | Where-Object Query -Match 'createTeam')
        $creates.Count | Should -Be 1
        $creates[0].Variables.input.slug | Should -Be 'tstsp1'
        $creates[0].Variables.input.slackChannel | Should -Be '#mon-tstsp1'
        $creates[0].Variables.input.purpose | Should -BeExactly 'Team for the tstsp1 project'
        @(Get-AddedMembers) | Sort-Object | Should -Be @('tstsp1/bob@example.com/MEMBER', 'tstsp1/carol@example.com/MEMBER')
        ($calls -join "`n") | Should -Not -Match '\.mail@'
    }

    It 'does not recreate an existing team found on a later page and reports members Nais cannot add' {
        { & $script:teamScript -Subscriptions d-tstsp2 3>$null } | Should -Throw '*tstsp2/unknown@example.com*'
        @(Get-GraphqlRequests | Where-Object Query -Match 'createTeam').Count | Should -Be 0
        @(Get-AddedMembers) | Should -Be @('tstsp2/unknown@example.com/MEMBER')
    }

    It 'warns about non-user group members' {
        $warnings = @(& $script:teamScript -Subscriptions d-tstsp1 3>&1)
        ($warnings -join ' ') | Should -Match "Skipping non-user member 'nested'"
    }

    It 'makes no changes with -WhatIf' {
        & $script:teamScript -Subscriptions d-tstsp1, d-tstsp2 -WhatIf 3>$null
        @(Get-GraphqlRequests | Where-Object Query -Match 'createTeam|addTeamMember').Count | Should -Be 0
    }

    It 'rejects invalid and reserved team names before calling any CLI' {
        { & $script:teamScript -Subscriptions x-tstsp1 } | Should -Throw '*must be named*'
        { & $script:teamScript -Subscriptions d-ab } | Should -Throw '*3-30 characters*'
        { & $script:teamScript -Subscriptions d-teamx } | Should -Throw '*reserved*'
        { & $script:teamScript -Subscriptions d-naisx } | Should -Throw '*reserved*'
        { & $script:teamScript -Subscriptions d-pg-x1 } | Should -Throw '*reserved*'
        @(Get-Content $env:TEAMS_TEST_LOG | Where-Object { $_ }).Count | Should -Be 0
    }

    It 'fails before touching Nais when an Entra group is missing' {
        { & $script:teamScript -Subscriptions d-missing } | Should -Throw '*does not exist*'
        @(Get-Content $env:TEAMS_TEST_LOG | Where-Object { $_ -like 'nais *' -or $_ -like 'graphql *' }).Count | Should -Be 0
    }

    It 'reports a helpful error when the Nais proxy cannot start' {
        $env:TEAMS_TEST_SCENARIO = 'not-logged-in'
        { & $script:teamScript -Subscriptions d-tstsp1 3>$null } | Should -Throw "*nais login*"
    }

    Context 'with a service account token' {
        BeforeEach {
            $env:TEAMS_TEST_SCENARIO = 'require-token'
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $script:consolePort = $listener.LocalEndpoint.Port
            $listener.Stop()
            $script:console = Start-Process -FilePath (Join-Path $TestDrive 'nais.exe') -ArgumentList 'api', 'proxy', '--listen', "localhost:$script:consolePort" -PassThru -WindowStyle Hidden
            $deadline = [DateTime]::UtcNow.AddSeconds(15)
            while ($true) {
                try {
                    [void] (Invoke-WebRequest -Uri "http://localhost:$script:consolePort/graphql" -Method Post -Body '{"query":"{ me }"}' -SkipHttpErrorCheck)
                    break
                }
                catch {
                    if ([DateTime]::UtcNow -gt $deadline) { throw }
                    Start-Sleep -Milliseconds 200
                }
            }
            Set-Content $env:TEAMS_TEST_LOG ''
        }

        AfterEach {
            if (-not $script:console.HasExited) {
                $script:console.Kill($true)
            }
            $script:console.WaitForExit()
        }

        It 'calls the API directly with the bearer token and without starting the Nais CLI' {
            $env:NAIS_API_TOKEN = 'test-token'
            & $script:teamScript -Subscriptions d-tstsp1 -ConsoleHost "http://localhost:$script:consolePort" 3>$null
            $requests = @(Get-GraphqlRequests)
            $requests.Count | Should -BeGreaterThan 0
            @($requests | Where-Object Auth -ne 'Bearer test-token').Count | Should -Be 0
            @($requests | Where-Object Query -Match 'createTeam').Count | Should -Be 1
            @(Get-AddedMembers) | Should -Be @('tstsp1/bob@example.com/MEMBER')
            @(Get-Content $env:TEAMS_TEST_LOG | Where-Object { $_ -like 'nais *' }).Count | Should -Be 0
            (Get-Content $env:TEAMS_TEST_LOG -Raw) | Should -Not -Match 'nais .*test-token'
        }

        It 'surfaces authentication failures from the API' {
            $env:NAIS_API_TOKEN = 'wrong-token'
            { & $script:teamScript -Subscriptions d-tstsp1 -ConsoleHost "http://localhost:$script:consolePort" 3>$null } | Should -Throw '*unauthorized*'
        }
    }

    It 'requires NAIS_API_TOKEN when -ConsoleHost is used' {
        { & $script:teamScript -Subscriptions d-tstsp1 -ConsoleHost console.example.cloud.nais.io } | Should -Throw '*NAIS_API_TOKEN*'
        @(Get-Content $env:TEAMS_TEST_LOG | Where-Object { $_ }).Count | Should -Be 0
    }
}
