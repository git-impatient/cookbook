# This script serves the current folder on localhost and opens it in the
# default browser. It is meant to be easy to run for someone who just wants
# to preview the files in this directory.
param(
    [int]$Port = 8000
)

$ErrorActionPreference = 'Stop'
[Console]::TreatControlCAsInput = $true

$HostName = '127.0.0.1'
$RootDir = (Get-Location).Path

# Return the HTTP content type to send for each file extension.
function Get-ContentType {
    param(
        [string]$Path
    )

    switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.css' { 'text/css; charset=utf-8' }
        '.gif' { 'image/gif' }
        '.htm' { 'text/html; charset=utf-8' }
        '.html' { 'text/html; charset=utf-8' }
        '.ico' { 'image/x-icon' }
        '.jpeg' { 'image/jpeg' }
        '.jpg' { 'image/jpeg' }
        '.js' { 'application/javascript; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.md' { 'text/markdown; charset=utf-8' }
        '.png' { 'image/png' }
        '.svg' { 'image/svg+xml' }
        '.txt' { 'text/plain; charset=utf-8' }
        '.webp' { 'image/webp' }
        default { 'application/octet-stream' }
    }
}

# Check whether the user pressed Q to stop the server cleanly.
function Test-StopRequested {
    while ([Console]::KeyAvailable) {
        $keyInfo = [Console]::ReadKey($true)

        if ($keyInfo.Key -eq [ConsoleKey]::Q) {
            return $true
        }
    }

    return $false
}

# Find the first free localhost port starting from the requested one.
function Get-FreePort {
    param(
        [int]$StartPort
    )

    $candidate = $StartPort

    while ($true) {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($HostName), $candidate)

        try {
            $listener.Start()
            $listener.Stop()
            return $candidate
        } catch {
            $candidate++
        }
    }
}

# Resolve the requested URL path and block access outside the served folder.
function Resolve-LocalPath {
    param(
        [string]$RequestPath
    )

    $relativePath = [Uri]::UnescapeDataString(($RequestPath -split '\?')[0]).TrimStart('/')
    $combinedPath = [IO.Path]::GetFullPath((Join-Path $RootDir $relativePath))
    $rootPrefix = $RootDir.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

    if ($combinedPath -ne $RootDir -and -not $combinedPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    return $combinedPath
}

# Write a plain text or HTML response body back to the browser.
function Write-StringResponse {
    param(
        [Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$ContentType,
        [string]$Content,
        [bool]$HeadOnly = $false
    )

    $buffer = [Text.Encoding]::UTF8.GetBytes($Content)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $buffer.Length

    if (-not $HeadOnly) {
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    }

    $Response.Close()
}

# Read a file from disk and send it to the browser.
function Write-FileResponse {
    param(
        [Net.HttpListenerResponse]$Response,
        [string]$Path,
        [bool]$HeadOnly = $false
    )

    $bytes = [IO.File]::ReadAllBytes($Path)
    $Response.StatusCode = 200
    $Response.ContentType = Get-ContentType -Path $Path
    $Response.ContentLength64 = $bytes.Length

    if (-not $HeadOnly) {
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    }

    $Response.Close()
}

# Serve index.html for folders when present, otherwise render a file list.
function Write-DirectoryResponse {
    param(
        [Net.HttpListenerResponse]$Response,
        [string]$DirectoryPath,
        [string]$RequestPath,
        [bool]$HeadOnly = $false
    )

    $indexPath = Join-Path $DirectoryPath 'index.html'
    if (Test-Path -LiteralPath $indexPath -PathType Leaf) {
        Write-FileResponse -Response $Response -Path $indexPath -HeadOnly:$HeadOnly
        return
    }

    $normalizedRequestPath = if ($RequestPath.EndsWith('/')) { $RequestPath } else { "$RequestPath/" }
    $parentPath = if ($normalizedRequestPath -eq '/') { $null } else { ($normalizedRequestPath.TrimEnd('/') -replace '/[^/]+$','') + '/' }

    $items = Get-ChildItem -LiteralPath $DirectoryPath | Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name
    $links = New-Object System.Collections.Generic.List[string]

    if ($null -ne $parentPath) {
        [void]$links.Add('<li><a href="' + $parentPath + '">..</a></li>')
    }

    foreach ($item in $items) {
        $suffix = if ($item.PSIsContainer) { '/' } else { '' }
        $itemUrl = $normalizedRequestPath + [Uri]::EscapeDataString($item.Name) + $suffix
        $label = [System.Net.WebUtility]::HtmlEncode($item.Name + $suffix)
        [void]$links.Add('<li><a href="' + $itemUrl + '">' + $label + '</a></li>')
    }

    $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Index of $normalizedRequestPath</title>
  <style>
    body { font-family: Segoe UI, sans-serif; margin: 2rem; }
    h1 { font-size: 1.4rem; }
    ul { list-style: none; padding: 0; }
    li { margin: 0.35rem 0; }
    a { color: #0b57d0; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <h1>Index of $([System.Net.WebUtility]::HtmlEncode($normalizedRequestPath))</h1>
  <ul>
    $($links -join "`n    ")
  </ul>
</body>
</html>
"@

    Write-StringResponse -Response $Response -StatusCode 200 -ContentType 'text/html; charset=utf-8' -Content $html -HeadOnly:$HeadOnly
}

# Finalize the listener address once a free port has been found.
$Port = Get-FreePort -StartPort $Port
$Prefix = "http://${HostName}:${Port}/"
$Listener = [Net.HttpListener]::new()
$Listener.Prefixes.Add($Prefix)
$Listener.Start()

Write-Host "Serving $RootDir"
Write-Host "Open $Prefix"
Write-Host ""
Write-Host "==================================" -ForegroundColor Yellow
Write-Host " TO STOP: Press Q in this window " -ForegroundColor Yellow
Write-Host "==================================" -ForegroundColor Yellow

# Open the default browser, but keep running even if that step fails.
try {
    Start-Process $Prefix | Out-Null
} catch {
    Write-Warning "Could not open browser automatically. Open $Prefix manually."
}

# Keep handling requests until the user stops the script.
try {
    $contextTask = $null

    while ($Listener.IsListening) {
        if (Test-StopRequested) {
            Write-Host ""
            Write-Host "Stopping server..." -ForegroundColor Yellow
            break
        }

        if ($null -eq $contextTask) {
            $contextTask = $Listener.GetContextAsync()
        }

        if (-not $contextTask.Wait(250)) {
            continue
        }

        try {
            $context = $contextTask.GetAwaiter().GetResult()
        } catch {
            if (-not $Listener.IsListening) {
                break
            }

            throw
        }

        $contextTask = $null

        $request = $context.Request
        $response = $context.Response
        $method = $request.HttpMethod.ToUpperInvariant()

        if ($method -ne 'GET' -and $method -ne 'HEAD') {
            Write-StringResponse -Response $response -StatusCode 405 -ContentType 'text/plain; charset=utf-8' -Content 'Method not allowed'
            continue
        }

        $localPath = Resolve-LocalPath -RequestPath $request.RawUrl
        if ($null -eq $localPath) {
            Write-StringResponse -Response $response -StatusCode 403 -ContentType 'text/plain; charset=utf-8' -Content 'Forbidden' -HeadOnly:($method -eq 'HEAD')
            continue
        }

        if (Test-Path -LiteralPath $localPath -PathType Container) {
            Write-DirectoryResponse -Response $response -DirectoryPath $localPath -RequestPath (($request.RawUrl -split '\?')[0]) -HeadOnly:($method -eq 'HEAD')
            continue
        }

        if (Test-Path -LiteralPath $localPath -PathType Leaf) {
            Write-FileResponse -Response $response -Path $localPath -HeadOnly:($method -eq 'HEAD')
            continue
        }

        Write-StringResponse -Response $response -StatusCode 404 -ContentType 'text/plain; charset=utf-8' -Content 'Not found' -HeadOnly:($method -eq 'HEAD')
    }
} finally {
    if ($Listener.IsListening) {
        $Listener.Stop()
    }

    $Listener.Close()
    [Console]::TreatControlCAsInput = $false
}