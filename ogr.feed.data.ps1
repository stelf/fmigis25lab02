# PowerShell script: Find ogr2ogr.exe, check PostgreSQL support, build DSN from .env, and import GeoJSON

param(
    [string]$geojson = "data\osi_ulici_26_osm_20180000.geojson",
    [string]$table = "osi_ulici_26_osm"
)


function Get-EnvFile {
    $dir = Get-Location
    while ($null -ne $dir) {
        $envPath = Join-Path $dir ".env"
        if (Test-Path $envPath) { return $envPath }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Get-DSNVars {
    param($envFile)
    $vars = @{
        PGUSER = $null
        PGPASSWORD = $null
        PGHOST = $null
        PGDATABASE = $null
        PGPORT = "5432"
    }
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*PGUSER\s*=\s*(.+)$') { $vars.PGUSER = $Matches[1].Trim() }
        elseif ($_ -match '^\s*PGPASSWORD\s*=\s*(.+)$') { $vars.PGPASSWORD = $Matches[1].Trim() }
        elseif ($_ -match '^\s*PGHOST\s*=\s*(.+)$') { $vars.PGHOST = $Matches[1].Trim() }
        elseif ($_ -match '^\s*PGDATABASE\s*=\s*(.+)$') { $vars.PGDATABASE = $Matches[1].Trim() }
        elseif ($_ -match '^\s*PGPORT\s*=\s*(.+)$') { $vars.PGPORT = $Matches[1].Trim() }
    }
    return $vars
}

# Find one  OGR2OGR with PostgreSQL support
if ($env:OGRWITHPG17 -and (Test-Path $env:OGRWITHPG17)) {
    # check cached value
    $ogr2ogrPg = $env:OGRWITHPG17
} else {
    Write-Host -ForegroundColor Magenta Looking for ogr2ogr.exe with proper PostgreSQL driver support
    # Find ogr2ogr.exe
    $ogr2ogrPaths = @()
    if (Get-Command fd -ErrorAction SilentlyContinue) {
        # Use fd with correct arguments
        $ogr2ogrPaths = fd ogr2ogr -tx / | Where-Object { $_ -match 'ogr2ogr\.exe$' }
    } else {
        $ogr2ogrPaths = Get-ChildItem -Path C:\ -Filter ogr2ogr.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }
    if (-not $ogr2ogrPaths) {
        Write-Error "Not a single ogr2ogr.exe found! Bummer..."
        exit 1
    }

    Write-Host -ForegroundColor Magenta found few, lets verify driver
    
    $ogr2ogrPg = $ogr2ogrPaths | Where-Object {
        (& $_ --formats 2>&1) -match 'PostgreSQL -vector-'
    } | Select-Object -First 1
    if ($ogr2ogrPg) {
        $env:OGRWITHPG17 = $ogr2ogrPg
    }
}

if (-not $ogr2ogrPg) {
    Write-Error "No ogr2ogr.exe with PostgreSQL support found."
    exit 2
}

# 3. Build DSN from .env
$envFile = Get-EnvFile
if (-not $envFile) {
    Write-Error ".env file not found."
    exit 3
}
$pgVars = Get-DSNVars $envFile
if (-not $pgVars.PGUSER -or -not $pgVars.PGPASSWORD -or -not $pgVars.PGHOST -or -not $pgVars.PGDATABASE) {
    Write-Error "Missing PGUSER, PGPASSWORD, PGHOST, or PGDATABASE in .env."
    exit 4
}
$dsn = "postgresql://$($pgVars.PGUSER):$($pgVars.PGPASSWORD)@$($pgVars.PGHOST):$($pgVars.PGPORT)/$($pgVars.PGDATABASE)"

# Summarize 
Write-Host -ForegroundColor Cyan "Preparing to run ogr2ogr with the following parameters:"
Write-Host -ForegroundColor Cyan "GeoJSON file: $geojson"
Write-Host -ForegroundColor Cyan "Target table: $table"
Write-Host -ForegroundColor Cyan "PostgreSQL DSN: postgresql://$($pgVars.PGUSER):<password_hidden>@$($pgVars.PGHOST):$($pgVars.PGPORT)/$($pgVars.PGDATABASE)"

# Execute the ogr2ogr command
&$ogr2ogrPg -progress -f PostgreSQL "PG:$dsn" $geojson -nln $table -lco GEOMETRY_NAME=geom -lco FID=id -nlt MultiLineString
