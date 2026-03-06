<# 
.SYNOPSIS
    Check for available updates for testssl-portal components.

.DESCRIPTION
    This script compares the currently pinned versions in build.sh against
    the latest available versions from Docker Hub and GitHub.
    
    Works on Windows without requiring Docker or WSL.

.EXAMPLE
    .\check-versions.ps1

.NOTES
    Exit codes: 0 = all up to date, 1 = updates available
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

# Colors
function Write-Info { param($Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Success { param($Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host $Message -ForegroundColor Red }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildSh = Join-Path $ScriptDir "build.sh"

# Counters
$Script:BaseimageUpdates = 0
$Script:GithubUpdates = 0

# ==============================================================================
# Helper Functions
# ==============================================================================

function Get-DefaultValue {
    param([string]$VarName)
    
    if (-not (Test-Path $BuildSh)) {
        return $null
    }
    
    $content = Get-Content $BuildSh -Raw
    $pattern = "DEFAULT_${VarName}=`"([^`"]*)`""
    if ($content -match $pattern) {
        return $Matches[1]
    }
    
    $pattern = "DEFAULT_${VarName}='([^']*)'"
    if ($content -match $pattern) {
        return $Matches[1]
    }
    
    return $null
}

function Compare-Versions {
    param([string]$Current, [string]$Latest)
    
    $currentClean = $Current -replace '^v', ''
    $latestClean = $Latest -replace '^v', ''
    
    if ($currentClean -eq $latestClean) {
        return "equal"
    }
    
    try {
        $currentVer = [Version]::new($currentClean -replace '-.*$', '')
        $latestVer = [Version]::new($latestClean -replace '-.*$', '')
        
        if ($latestVer -gt $currentVer) {
            return "newer"
        } else {
            return "older"
        }
    } catch {
        if ($latestClean -gt $currentClean) {
            return "newer"
        }
        return "older"
    }
}

# ==============================================================================
# Read Current Versions from build.sh
# ==============================================================================

Write-Info "=== Checking for updates ==="
Write-Host "Reading current versions from build.sh..."
Write-Host ""

if (-not (Test-Path $BuildSh)) {
    Write-Error "ERROR: build.sh not found at $BuildSh"
    exit 1
}

$CurrentBaseimage = Get-DefaultValue "BASEIMAGE_VERSION"
$CurrentTestssl = Get-DefaultValue "TESTSSL_VERSION"

if ([string]::IsNullOrEmpty($CurrentBaseimage)) {
    $CurrentBaseimage = "bookworm-20250224-slim"
}

if ([string]::IsNullOrEmpty($CurrentTestssl)) {
    $CurrentTestssl = "v3.2.3"
}

Write-Host "Current versions:"
Write-Host "  Base image:   debian:$CurrentBaseimage"
Write-Host "  testssl.sh:   $CurrentTestssl"
Write-Host ""

# ==============================================================================
# Check Base Image (Docker Hub API)
# ==============================================================================

Write-Info "--- Base Image (Docker Hub) ---"
Write-Host "Repository: https://hub.docker.com/_/debian"

function Check-DebianTags {
    param([string]$CurrentTag)
    
    # Parse current tag: bookworm-20250224-slim or bookworm-slim
    $currentRelease = ""
    $currentDate = ""
    
    if ($CurrentTag -match '^([a-z]+)-(\d{8})-slim$') {
        $currentRelease = $Matches[1]
        $currentDate = $Matches[2]
        Write-Host "  Current: debian:$CurrentTag (release: $currentRelease, date: $currentDate)"
    } elseif ($CurrentTag -match '^([a-z]+)-slim$') {
        $currentRelease = $Matches[1]
        $currentDate = "rolling"
        Write-Host "  Current: debian:$CurrentTag (release: $currentRelease, rolling tag)"
    } else {
        Write-Warning "  WARNING: Unrecognized tag format: $CurrentTag"
        return
    }
    
    try {
        # Fetch tags for current release
        $apiUrl = "https://hub.docker.com/v2/repositories/library/debian/tags?page_size=100&name=$currentRelease"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 30
        
        # Extract dated slim tags (e.g., bookworm-20250224-slim)
        $datedTags = $response.results | 
            Where-Object { $_.name -match "^$currentRelease-\d{8}-slim$" } | 
            Select-Object -ExpandProperty name |
            Sort-Object -Descending
        
        if (-not $datedTags) {
            Write-Warning "  WARNING: No dated tags found for $currentRelease"
            return
        }
        
        $latestDated = $datedTags | Select-Object -First 1
        $latestDate = $latestDated -replace "^$currentRelease-" -replace '-slim$'
        
        # Compare dates
        if ($currentDate -eq "rolling") {
            Write-Warning "  Using rolling tag. Latest pinned: $latestDated"
            Write-Warning "  Recommendation: Pin to $latestDated for reproducible builds"
            $Script:BaseimageUpdates = 1
        } elseif ($currentDate -eq $latestDate) {
            Write-Host "  Same release ($currentRelease): " -NoNewline
            Write-Success "$CurrentTag (up to date)"
        } elseif ($currentDate -lt $latestDate) {
            Write-Host "  Same release ($currentRelease): current $CurrentTag -> latest $latestDated " -NoNewline
            Write-Warning "(NEWER)"
            $Script:BaseimageUpdates = 1
        } else {
            Write-Host "  Same release ($currentRelease): " -NoNewline
            Write-Success "$CurrentTag (up to date)"
        }
        
        # Check for new release lines
        $apiUrl = "https://hub.docker.com/v2/repositories/library/debian/tags?page_size=100&name=slim"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 30
        
        $allReleases = $response.results | 
            Where-Object { $_.name -match '^[a-z]+-slim$' } | 
            Select-Object -ExpandProperty name |
            ForEach-Object { $_ -replace '-slim$' } |
            Sort-Object -Unique
        
        if ($allReleases) {
            $releasesList = $allReleases -join ", "
            Write-Host "  Available releases: $releasesList"
        }
        
    } catch {
        Write-Warning "  WARNING: Could not fetch tags from Docker Hub: $_"
    }
}

Check-DebianTags $CurrentBaseimage
Write-Host ""

# ==============================================================================
# Check testssl.sh (GitHub API)
# ==============================================================================

Write-Info "--- GitHub Components ---"

function Check-GitHubRelease {
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$Current,
        [string]$Name
    )
    
    Write-Host "$Name (https://github.com/$Owner/$Repo)"
    
    try {
        $apiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
        $headers = @{ "User-Agent" = "check-versions-ps1" }
        
        try {
            $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
            $latest = $response.tag_name
        } catch {
            $apiUrl = "https://api.github.com/repos/$Owner/$Repo/tags"
            $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
            $latest = $response[0].name
        }
        
        if ([string]::IsNullOrEmpty($latest)) {
            Write-Warning "  WARNING: Could not determine latest version"
            return
        }
        
        $latestClean = $latest -replace '^v', ''
        $currentClean = $Current -replace '^v', ''
        
        if ($currentClean -eq $latestClean -or $Current -eq $latest) {
            Write-Host "  current $Current -> latest $latest " -NoNewline
            Write-Success "(up to date)"
        } else {
            $cmp = Compare-Versions $currentClean $latestClean
            if ($cmp -eq "newer") {
                Write-Host "  current $Current -> latest $latest " -NoNewline
                Write-Warning "(NEWER)"
                $Script:GithubUpdates++
            } else {
                Write-Host "  current $Current -> latest $latest " -NoNewline
                Write-Success "(up to date)"
            }
        }
        
    } catch {
        Write-Warning "  WARNING: Could not fetch releases from GitHub: $_"
    }
}

Check-GitHubRelease "testssl" "testssl.sh" $CurrentTestssl "testssl.sh"
Write-Host ""

# ==============================================================================
# Summary
# ==============================================================================

Write-Info "=== Summary ==="

$TotalUpdates = $Script:BaseimageUpdates + $Script:GithubUpdates

if ($Script:BaseimageUpdates -gt 0) {
    Write-Warning "A new base image line is available (consider migrating)."
}

if ($Script:GithubUpdates -gt 0) {
    Write-Warning "$($Script:GithubUpdates) GitHub component(s) have newer versions."
}

if ($TotalUpdates -eq 0) {
    Write-Success "All components are up to date."
    exit 0
} else {
    Write-Host ""
    Write-Host "Consider updating build.sh and releasing a new image."
    exit 1
}
