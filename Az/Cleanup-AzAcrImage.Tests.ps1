BeforeAll {
    $script:cleanupScript = Join-Path $PSScriptRoot 'Cleanup-AzAcrImage.ps1'
    $script:previousPath = $env:PATH
    $script:previousLog = $env:ACR_TEST_LOG
    $script:previousKubeScenario = $env:ACR_TEST_KUBE_SCENARIO
    $stubDir = Join-Path $TestDrive 'stub'
    New-Item -ItemType Directory -Path $stubDir | Out-Null
    $source = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Web;

public class Stub {
    const string LoginServer = "testacr.azurecr.io";
    static string Log => Environment.GetEnvironmentVariable("ACR_TEST_LOG");
    static readonly object Lock = new object();

    static void Append(string line) {
        lock (Lock) {
            for (int i = 0; ; i++) {
                try { File.AppendAllText(Log, line + Environment.NewLine); return; }
                catch (IOException) when (i < 50) { System.Threading.Thread.Sleep(20); }
            }
        }
    }

    static string D(char c) => "sha256:" + new string(c, 64);

    static readonly Dictionary<string, (string Digest, string[] Tags)[]> Manifests = new Dictionary<string, (string, string[])[]> {
        ["team-a/api"] = new[] { (D('1'), new[] { "v1" }), (D('2'), new[] { "v2" }), (D('3'), new[] { "latest" }), (D('4'), new string[0]), (D('5'), new[] { "v5" }) },
        ["team-a/web"] = new[] { (D('6'), new[] { "old" }), (D('7'), new[] { "cur" }) },
        ["team-b/svc"] = new[] { (D('8'), new[] { "x" }) },
        ["orphan/app"] = new[] { (D('b'), new[] { "y" }) },
        ["cloud-platform/tool"] = new[] { (D('9'), new[] { "a" }), (D('a'), new[] { "b" }) },
    };

    static (string Namespace, object Resource) Pod(string ns, string image, string imageId = null, string annotationImage = null) => (ns, new {
        apiVersion = "v1",
        kind = "Pod",
        metadata = new { name = "pod", @namespace = ns, annotations = new { image = annotationImage ?? "" } },
        spec = new { containers = new[] { new { name = "c", image } } },
        status = new { containerStatuses = new[] { new { name = "c", image, imageID = imageId ?? "" } } },
    });

    static readonly Dictionary<string, (string Namespace, object Resource)[]> PodsByContext = new Dictionary<string, (string Namespace, object Resource)[]> {
        ["d-aks"] = new[] {
            Pod("team-a", LoginServer + "/team-a/api:v2"),
            Pod("team-a", LoginServer + "/team-a/web:cur", null, LoginServer + "/team-b/svc:x"),
            Pod("kube-system", "mcr.microsoft.com/other:1"),
        },
        ["p-aks"] = new[] {
            Pod("team-a", "other.azurecr.io/team-a/api:v1", "docker-pullable://" + LoginServer + "/team-a/api@" + D('4')),
            Pod("cmgt", LoginServer + "/cloud-platform/tool:a"),
        },
    };

    static readonly Dictionary<string, string[]> NamespacesByContext = new Dictionary<string, string[]> {
        ["d-aks"] = new[] { "team-a", "team-b", "kube-system" },
        ["p-aks"] = new[] { "team-a", "cmgt" },
    };

    static string Jwt(object claims) {
        string Encode(string s) => Convert.ToBase64String(Encoding.UTF8.GetBytes(s)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        return Encode("{\"alg\":\"none\"}") + "." + Encode(JsonSerializer.Serialize(claims)) + ".sig";
    }

    static string ScopeOf(string token) {
        try {
            string payload = token.Split('.')[1].Replace('-', '+').Replace('_', '/');
            payload += new string('=', (4 - payload.Length % 4) % 4);
            return JsonDocument.Parse(Convert.FromBase64String(payload)).RootElement.GetProperty("scope").GetString();
        }
        catch { return null; }
    }

    static int Kubectl(string[] args) {
        string context = args[Array.IndexOf(args, "--context") + 1];
        int nsIndex = Array.IndexOf(args, "--namespace");
        string ns = nsIndex >= 0 ? args[nsIndex + 1] : null;
        System.Threading.Thread.Sleep(200);
        if (args.Contains("namespaces")) {
            var items = NamespacesByContext[context].Select(n => new { metadata = new { name = n } });
            Console.WriteLine(JsonSerializer.Serialize(new { apiVersion = "v1", kind = "List", items }));
            return 0;
        }
        if (Environment.GetEnvironmentVariable("ACR_TEST_KUBE_SCENARIO") == "fail" && context == "p-aks") {
            Console.Error.WriteLine("error: the server has asked for the client to provide credentials");
            return 1;
        }
        var pods = PodsByContext[context].Where(p => ns == null || p.Namespace == ns).Select(p => p.Resource).ToArray();
        Console.WriteLine(JsonSerializer.Serialize(new { apiVersion = "v1", kind = "List", items = pods }));
        return 0;
    }

    static int Az(string[] args) {
        string joined = string.Join(" ", args);
        if (joined.StartsWith("acr show ")) { Console.WriteLine(LoginServer); return 0; }
        if (joined.StartsWith("account get-access-token ")) {
            Console.WriteLine(JsonSerializer.Serialize(new { accessToken = "aad-token", tenant = "tenant-id", expiresOn = "2099-01-01" }));
            return 0;
        }
        if (joined.StartsWith("acr repository list ")) { Console.WriteLine(JsonSerializer.Serialize(Manifests.Keys.ToArray())); return 0; }
        Console.Error.WriteLine("unexpected az call: " + joined);
        return 2;
    }

    // Mock ACR data plane.
    static string scenario = "normal";
    static readonly HashSet<string> seen = new HashSet<string>();

    static (int, string, Dictionary<string, string>) Handle(HttpListenerRequest request, string body) {
        var headers = new Dictionary<string, string>();
        string path = request.Url.AbsolutePath;
        var query = HttpUtility.ParseQueryString(request.Url.Query);
        var form = HttpUtility.ParseQueryString(body ?? "");

        if (path == "/_test/reset") {
            lock (Lock) { scenario = body; seen.Clear(); }
            return (200, "{}", headers);
        }
        if (path == "/oauth2/exchange") {
            if (form["grant_type"] != "access_token" || form["service"] != LoginServer || form["access_token"] != "aad-token" || form["tenant"] != "tenant-id") {
                return (400, "{\"errors\":\"bad exchange\"}", headers);
            }
            return (200, JsonSerializer.Serialize(new { refresh_token = Jwt(new { exp = DateTimeOffset.UtcNow.AddHours(3).ToUnixTimeSeconds() }) }), headers);
        }
        if (path == "/oauth2/token") {
            if (form["grant_type"] != "refresh_token" || form["service"] != LoginServer || string.IsNullOrEmpty(form["refresh_token"])) {
                return (400, "{\"errors\":\"bad token request\"}", headers);
            }
            Append("server token " + form["scope"]);
            return (200, JsonSerializer.Serialize(new { access_token = Jwt(new { exp = DateTimeOffset.UtcNow.AddHours(1).ToUnixTimeSeconds(), scope = form["scope"] }) }), headers);
        }

        string auth = request.Headers["Authorization"] ?? "";
        string tokenScope = auth.StartsWith("Bearer ") ? ScopeOf(auth.Substring(7)) : null;
        bool firstAttempt;
        lock (Lock) { firstAttempt = seen.Add(request.HttpMethod + " " + request.Url.PathAndQuery); }

        if (scenario == "throttle" && firstAttempt) {
            headers["Retry-After"] = "1";
            Append("server 429 " + request.HttpMethod + " " + path);
            return (429, "{\"errors\":[{\"code\":\"TOOMANYREQUESTS\"}]}", headers);
        }

        const string listPrefix = "/acr/v1/";
        if (request.HttpMethod == "GET" && path.StartsWith(listPrefix) && path.EndsWith("/_manifests")) {
            string repo = path.Substring(listPrefix.Length, path.Length - listPrefix.Length - "/_manifests".Length);
            if (scenario == "expire" && firstAttempt && query["last"] == null) {
                Append("server 401 " + path);
                return (401, "{\"errors\":[{\"code\":\"UNAUTHORIZED\"}]}", headers);
            }
            if (tokenScope != "repository:" + repo + ":metadata_read") { return (401, "{\"errors\":\"wrong scope " + tokenScope + "\"}", headers); }
            Append("server list " + repo + " last=" + (query["last"] ?? "") + " n=" + query["n"] + " orderby=" + query["orderby"]);
            if (!Manifests.ContainsKey(repo)) { return (404, "{\"errors\":[{\"code\":\"NAME_UNKNOWN\"}]}", headers); }
            var all = Manifests[repo];
            int start = query["last"] == null ? 0 : Array.FindIndex(all, m => m.Digest == query["last"]) + 1;
            var page = all.Skip(start).Take(2).ToArray();
            if (start + page.Length < all.Length) {
                headers["Link"] = "</acr/v1/" + repo + "/_manifests?last=" + page.Last().Digest + "&n=2&orderby=timeasc>; rel=\"next\"";
            }
            return (200, JsonSerializer.Serialize(new { registry = LoginServer, imageName = repo, manifests = page.Select(m => new { digest = m.Digest, tags = m.Tags }) }), headers);
        }

        if (request.HttpMethod == "DELETE" && path.StartsWith("/v2/") && path.Contains("/manifests/")) {
            int split = path.IndexOf("/manifests/");
            string repo = path.Substring(4, split - 4);
            string digest = path.Substring(split + "/manifests/".Length);
            if (tokenScope != "repository:" + repo + ":delete") { return (401, "{\"errors\":\"wrong scope " + tokenScope + "\"}", headers); }
            if (scenario == "forbidden-delete" && repo == "team-a/web") {
                return (403, "{\"errors\":[{\"code\":\"DENIED\"}]}", headers);
            }
            Append("server delete " + repo + "@" + digest);
            return (202, "", headers);
        }

        return (404, "{}", headers);
    }

    static int Serve(string prefix) {
        var listener = new HttpListener();
        listener.Prefixes.Add(prefix);
        listener.Start();
        Console.WriteLine("listening");
        while (true) {
            var context = listener.GetContext();
            System.Threading.ThreadPool.QueueUserWorkItem(_ => {
                try {
                    string body = new StreamReader(context.Request.InputStream).ReadToEnd();
                    var (status, response, headers) = Handle(context.Request, body);
                    foreach (var header in headers) { context.Response.Headers[header.Key] = header.Value; }
                    byte[] bytes = Encoding.UTF8.GetBytes(response);
                    context.Response.StatusCode = status;
                    context.Response.ContentType = "application/json";
                    context.Response.OutputStream.Write(bytes, 0, bytes.Length);
                    context.Response.Close();
                }
                catch (Exception ex) { Append("server error " + ex); }
            });
        }
    }

    public static int Main(string[] args) {
        string program = Path.GetFileNameWithoutExtension(Environment.ProcessPath);
        if (program == "acrserver") { return Serve(args[0]); }
        Append(program + " " + string.Join(" ", args));
        if (program == "kubectl") { return Kubectl(args); }
        if (program == "az") { return Az(args); }
        return 3;
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
    foreach ($command in @('az', 'kubectl', 'acrserver')) {
        Copy-Item (Join-Path $stubDir 'out\Stub.exe') (Join-Path $TestDrive "$command.exe")
    }

    $env:PATH = "$TestDrive;$env:PATH"
    $env:ACR_TEST_LOG = Join-Path $TestDrive 'calls.log'
    Set-Content $env:ACR_TEST_LOG ''

    $portListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $portListener.Start()
    $port = $portListener.LocalEndpoint.Port
    $portListener.Stop()

    $script:endpoint = "http://localhost:$port"
    $script:server = Start-Process -FilePath (Join-Path $TestDrive 'acrserver.exe') -ArgumentList "$script:endpoint/" -PassThru -WindowStyle Hidden
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ($true) {
        try {
            Invoke-RestMethod -Method Post -Uri "$script:endpoint/_test/reset" -Body 'normal' | Out-Null
            break
        }
        catch {
            if ([DateTime]::UtcNow -gt $deadline) { throw "Mock ACR server did not start: $_" }
            Start-Sleep -Milliseconds 200
        }
    }

    function D([char] $c) { "sha256:$([string]::new($c, 64))" }

    function Invoke-Cleanup {
        param([hashtable] $Parameters = @{})

        $arguments = @{
            RegistryName       = 'testacr'
            KubeContext        = @('d-aks', 'p-aks')
            SkipAksCredentials = $true
            RegistryEndpoint   = $script:endpoint
        } + $Parameters

        & $script:cleanupScript @arguments 6>&1 3>&1 | ForEach-Object { "$_" }
    }

    function Get-ServerLog([string] $Kind) {
        @(Get-Content $env:ACR_TEST_LOG | Where-Object { $_ -like "server $Kind *" } | ForEach-Object { $_.Substring("server $Kind ".Length) })
    }

    $script:expectedDeletes = @(
        "team-a/api@$(D '1')",
        "team-a/api@$(D '5')",
        "team-a/web@$(D '6')",
        "team-b/svc@$(D '8')",
        "cloud-platform/tool@$(D 'a')"
    ) | Sort-Object
}

AfterAll {
    if ($script:server -and -not $script:server.HasExited) {
        Stop-Process -Id $script:server.Id
    }

    $env:PATH = $script:previousPath
    $env:ACR_TEST_LOG = $script:previousLog
    $env:ACR_TEST_KUBE_SCENARIO = $script:previousKubeScenario
}

Describe 'Cleanup-AzAcrImage' {
    BeforeEach {
        $env:ACR_TEST_KUBE_SCENARIO = 'normal'
        Set-Content $env:ACR_TEST_LOG ''
        Invoke-RestMethod -Method Post -Uri "$script:endpoint/_test/reset" -Body 'normal' | Out-Null
    }

    It 'lists every page of manifests and only reports unused manifests in a dry run' {
        $output = Invoke-Cleanup

        @(Get-ServerLog 'delete').Count | Should -Be 0
        @($output | Where-Object { $_ -match '^Would delete (\S+@\S+)$' } | ForEach-Object { $Matches[1] }) | Sort-Object | Should -Be $script:expectedDeletes
        Get-ServerLog 'list' | Should -Contain "team-a/api last=$(D '4') n=2 orderby=timeasc"
        (Get-ServerLog 'list') -join "`n" | Should -Not -Match 'orphan/app'
        $output | Should -Contain "Dry run complete. Would delete 5 unused image manifest(s) from registry 'testacr'. Pass -EnableDelete to delete them."
    }

    It 'ignores image values in Kubernetes metadata and protects running digests' {
        $output = Invoke-Cleanup
        $output | Should -Contain "Would delete team-b/svc@$(D '8')"
        $output | Should -Not -Contain "Would delete team-a/api@$(D '4')"
        $output | Should -Not -Contain "Would delete team-a/api@$(D '3')"
    }

    It 'deletes exactly the unused manifests with repository-scoped tokens' {
        $output = Invoke-Cleanup -Parameters @{ EnableDelete = $true }

        Get-ServerLog 'delete' | Sort-Object | Should -Be $script:expectedDeletes
        Get-ServerLog 'token' | Should -Contain 'repository:team-a/api:delete'
        Get-ServerLog 'token' | Should -Contain 'repository:team-a/api:metadata_read'
        @(Get-ServerLog 'token' | Where-Object { $_ -eq 'repository:team-a/api:metadata_read' }).Count | Should -Be 1
        $output | Should -Contain "Deleted 5 of 5 unused image manifest(s) from registry 'testacr'."
        @(Get-Content $env:ACR_TEST_LOG | Where-Object { $_ -like 'az acr manifest*' -or $_ -like 'az acr repository delete*' }).Count | Should -Be 0
    }

    It 'retries throttled list and delete requests' {
        Invoke-RestMethod -Method Post -Uri "$script:endpoint/_test/reset" -Body 'throttle' | Out-Null
        Invoke-Cleanup -Parameters @{ EnableDelete = $true } | Out-Null

        (Get-ServerLog '429').Count | Should -BeGreaterThan 5
        Get-ServerLog 'delete' | Sort-Object | Should -Be $script:expectedDeletes
    }

    It 'requests a new access token when the registry rejects a cached one' {
        Invoke-RestMethod -Method Post -Uri "$script:endpoint/_test/reset" -Body 'expire' | Out-Null
        Invoke-Cleanup -Parameters @{ EnableDelete = $true } | Out-Null

        @(Get-ServerLog 'token' | Where-Object { $_ -eq 'repository:team-a/api:metadata_read' }).Count | Should -Be 2
        Get-ServerLog 'delete' | Sort-Object | Should -Be $script:expectedDeletes
    }

    It 'fails after attempting all deletes when some are rejected' {
        Invoke-RestMethod -Method Post -Uri "$script:endpoint/_test/reset" -Body 'forbidden-delete' | Out-Null

        { Invoke-Cleanup -Parameters @{ EnableDelete = $true; ErrorAction = 'Continue' } 2>$null } | Should -Throw '*Failed to delete 1 of 5 manifest(s)*'
        Get-ServerLog 'delete' | Sort-Object | Should -Be @($script:expectedDeletes | Where-Object { $_ -notlike 'team-a/web@*' })
    }

    It 'stops before touching the registry when a kubectl read fails' {
        $env:ACR_TEST_KUBE_SCENARIO = 'fail'

        { Invoke-Cleanup -Parameters @{ EnableDelete = $true } } | Should -Throw "*Failed to read Kubernetes resources from context 'p-aks'*provide credentials*"
        @(Get-Content $env:ACR_TEST_LOG | Where-Object { $_ -like 'server *' }).Count | Should -Be 0
    }

    It 'only scans the namespaces of included repository prefixes' {
        $output = Invoke-Cleanup -Parameters @{ IncludeRepositoryPrefix = 'team-a' }

        $kubectlReads = @(Get-Content $env:ACR_TEST_LOG | Where-Object { $_ -like 'kubectl * get pods,*' })
        $kubectlReads.Count | Should -Be 2
        $kubectlReads | ForEach-Object { $_ | Should -Match '--namespace team-a ' }
        @($output | Where-Object { $_ -match '^Would delete (\S+@\S+)$' } | ForEach-Object { $Matches[1] }) | Sort-Object |
            Should -Be @($script:expectedDeletes | Where-Object { $_ -like 'team-a/*' })
    }

    It 'makes no deletions with -WhatIf' {
        Invoke-Cleanup -Parameters @{ EnableDelete = $true; WhatIf = $true } | Out-Null
        @(Get-ServerLog 'delete').Count | Should -Be 0
    }
}
