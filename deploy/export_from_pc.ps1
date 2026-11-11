# Export PeakSell Studio from the Windows PC so the VPS can take over.
#
#   powershell -ExecutionPolicy Bypass -File deploy\export_from_pc.ps1
#
# Writes deploy\bundle\{peaksell.dump, media.tgz, .env} and then STOPS the PC
# stack. Stopping is mandatory: two workers would publish every post twice,
# and two tunnel connectors would split traffic between the machines.
# deploy\bundle\ is git-ignored (it holds secrets) - never commit it.
param([switch]$KeepRunning)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$env:Path = 'C:\Program Files\Docker\Docker\resources\bin;' + $env:Path
$files = @('-f', 'docker-compose.yml', '-f', 'docker-compose.prod.yml', '-f', 'docker-compose.tunnel.yml')
$bundle = Join-Path $repo 'deploy\bundle'
New-Item -ItemType Directory -Force $bundle | Out-Null

Write-Host '1/4 Stopping app, worker and tunnel (database stays up for the dump)...'
docker compose @files stop app worker cloudflared caddy

Write-Host '2/4 Dumping database...'
docker compose @files exec -T postgres pg_dump -U postgres -Fc -f /tmp/peaksell.dump peaksell
$pg = (docker compose @files ps -q postgres).Trim()
docker cp "${pg}:/tmp/peaksell.dump" (Join-Path $bundle 'peaksell.dump')

Write-Host '3/4 Archiving uploaded media...'
$project = (Split-Path -Leaf $repo)
docker run --rm -v "${project}_media_data:/m:ro" -v "${bundle}:/out" alpine:3.20 tar czf /out/media.tgz -C /m .

Copy-Item (Join-Path $repo '.env') (Join-Path $bundle '.env') -Force

if (-not $KeepRunning) {
    Write-Host '4/4 Stopping the whole PC stack...'
    docker compose @files down
}
Get-ChildItem $bundle | Select-Object Name, Length | Format-Table -AutoSize
Write-Host "Bundle ready: $bundle"
