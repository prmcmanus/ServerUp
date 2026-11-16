# ===== Addresses to test: add, remove or edit lines here =====
# Port check: Name + Host + Port      Page check: Name + Url
$Targets = @(
    [pscustomobject]@{ Name = 'bbc.co.uk on port 443'; Host = 'bbc.co.uk'; Port = 443 }
    [pscustomobject]@{ Name = 'bbc.co.uk website';     Url  = 'https://www.bbc.co.uk' }
#   [pscustomobject]@{ Name = 'Example server';             Host = 'server3.example.com';     Port = 1433 }
#   [pscustomobject]@{ Name = 'Example webpage';            Url  = 'server3.example.com' }

)

$IntervalSeconds = 10     # time between rounds of tests
$TimeoutMs       = 3000   # port checks: how long to wait before counting as failed
$HttpTimeoutSec  = 10     # page checks: how long to wait for the page

# Allow TLS 1.2 (Windows PowerShell 5.1 may not by default) and hide the download progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

function Get-Address($t) {
    if ($t.Url) { $t.Url } else { "$($t.Host):$($t.Port)" }
}

# ===== Choose which addresses to test =====
$selected = @($true) * $Targets.Count   # all start switched on

while ($true) {
    Clear-Host
    Write-Host "Network Connection Test - choose addresses`n"
    for ($i = 0; $i -lt $Targets.Count; $i++) {
        $mark = if ($selected[$i]) { 'X' } else { ' ' }
        Write-Host ("  {0,2}. [{1}] {2}  ({3})" -f ($i + 1), $mark, $Targets[$i].Name, (Get-Address $Targets[$i]))
    }
    Write-Host "`nNumber(s) to toggle (e.g. 2 or 1,3)  |  A = all  |  N = none  |  Enter = start  |  Q = quit"
    $choice = (Read-Host 'Choice').Trim()

    if ($choice -eq '') {
        if ($selected -contains $true) { break }
        Write-Host 'Select at least one address.' -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
    elseif ($choice -match '^[Qq]$') { return }
    elseif ($choice -match '^[Aa]$') { for ($i = 0; $i -lt $selected.Count; $i++) { $selected[$i] = $true } }
    elseif ($choice -match '^[Nn]$') { for ($i = 0; $i -lt $selected.Count; $i++) { $selected[$i] = $false } }
    else {
        foreach ($n in $choice -split '[,\s]+') {
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $Targets.Count) {
                $selected[[int]$n - 1] = -not $selected[[int]$n - 1]
            }
        }
    }
}

# ===== Build the list of active targets with their own counters =====
$active = @(for ($i = 0; $i -lt $Targets.Count; $i++) {
    if ($selected[$i]) {
        [pscustomobject]@{
            Name = $Targets[$i].Name; Host = $Targets[$i].Host; Port = $Targets[$i].Port; Url = $Targets[$i].Url
            Address = Get-Address $Targets[$i]
            Pass = 0; Fail = 0; Last = '-'; Ok = $false; LastOk = '-'; LastFail = '-'
        }
    }
})



function Test-Port([string]$HostName, [int]$Port, [int]$TimeoutMs) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        if ($task.Wait($TimeoutMs) -and $client.Connected) { return 'OK' } else { return 'FAIL' }
    }
    catch { return 'FAIL' }          # DNS failure, connection refused, etc.
    finally { $client.Dispose() }
}

function Test-Url([string]$Url, [int]$TimeoutSec) {
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -UseDefaultCredentials -TimeoutSec $TimeoutSec
        return "HTTP $([int]$r.StatusCode)"
    }
    catch {
        # Server answered with an error code (404, 500...) vs. no answer at all
        if ($_.Exception.Response) { return "HTTP $([int]$_.Exception.Response.StatusCode)" }
        return 'FAIL'
    }
}

# ===== Test loop (Ctrl+C to stop) =====
$fmt = '{0,-26} {1,-29} {2,-9} {3,6} {4,6} {5,6}  {6,-14}  {7,-14}'
while ($true) {
    foreach ($t in $active) {
        $t.Last = if ($t.Url) { Test-Url $t.Url $HttpTimeoutSec } else { Test-Port $t.Host $t.Port $TimeoutMs }
        $t.Ok   = $t.Last -eq 'OK' -or ($t.Last -match '^HTTP (\d+)$' -and [int]$Matches[1] -lt 400)
        $now    = Get-Date -Format 'dd/MM HH:mm:ss'
        if ($t.Ok) { $t.Pass++; $t.LastOk   = $now }
        else       { $t.Fail++; $t.LastFail = $now }
    }

    Clear-Host
    Write-Host 'Network Connection Test'
    Write-Host "Checking every $IntervalSeconds seconds - last run $(Get-Date -Format 'HH:mm:ss') - Ctrl+C to stop`n"
    Write-Host ($fmt -f 'Name', 'Address', 'Status', 'Pass', 'Fail', 'Total', 'Last OK', 'Last Fail')
    Write-Host ($fmt -f '----', '-------', '------', '----', '----', '-----', '-------', '---------')
    foreach ($t in $active) {
        $colour = if ($t.Ok) { 'Green' } else { 'Red' }
        $addr = if ($t.Address.Length -gt 29) { $t.Address.Substring(0, 28) + '~' } else { $t.Address }
        Write-Host ($fmt -f $t.Name, $addr, $t.Last, $t.Pass, $t.Fail, ($t.Pass + $t.Fail), $t.LastOk, $t.LastFail) -ForegroundColor $colour

    }

    Start-Sleep -Seconds $IntervalSeconds
}
