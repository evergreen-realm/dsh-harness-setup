<#
.SYNOPSIS
    One-command setup for DeepSeek Harness + Evergreen Memory Plugin.
.DESCRIPTION
    Installs and configures DeepSeek Harness desktop environment, builds the
    zero-dependency memory plugin, provisions cordis patches, and establishes
    permanent profile symlinks.
#>

[CmdletBinding()]
param(
    [switch]$SkipLaunch,
    [string]$OllamaKey = ""
)

$ErrorActionPreference = "Stop"
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   DeepSeek Harness + Evergreen Memory Plugin Setup       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. PREREQUISITES CHECK
Write-Host "[1/6] Checking prerequisites..." -ForegroundColor Yellow

# Check Node.js
try {
    $nodeVersionRaw = node -v
    $nodeMajor = [int]($nodeVersionRaw -replace '^v(\d+)\..*$', '$1')
    $nodeMinor = [int]($nodeVersionRaw -replace '^v\d+\.(\d+)\..*$', '$1')
    Write-Host "  ✓ Found Node.js: $nodeVersionRaw" -ForegroundColor Green

    if ($nodeMajor -lt 22 -or ($nodeMajor -eq 22 -and $nodeMinor -lt 6)) {
        Write-Warning "Node.js >= 22.6.0 is required for native stripTypeScriptTypes. Current: $nodeVersionRaw"
        Write-Host "Please update Node.js from https://nodejs.org/" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ✗ Node.js is not installed or not in PATH." -ForegroundColor Red
    Write-Host "  Please install Node.js >= 22.6.0 from https://nodejs.org/" -ForegroundColor Red
    exit 1
}

# Check Git
try {
    $gitVersion = git --version
    Write-Host "  ✓ Found Git: $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Git is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

# 2. CHECK / INSTALL DEEPSEEK HARNESS
Write-Host "`n[2/6] Verifying DeepSeek Harness installation..." -ForegroundColor Yellow
$dshExePath = "$env:LOCALAPPDATA\Programs\DeepSeek Harness\DeepSeek Harness.exe"

if (Test-Path $dshExePath) {
    Write-Host "  ✓ DeepSeek Harness is installed at: $dshExePath" -ForegroundColor Green
} else {
    Write-Host "  ! DeepSeek Harness is not found in standard location." -ForegroundColor Yellow
    Write-Host "  Downloading/installing official DeepSeek Harness..." -ForegroundColor Cyan

    $downloadUrl = "https://download.deepseek.com/dsh-desk/feeds/win-x64/DeepSeek%20Harness%20Setup.exe"
    $installerPath = "$env:TEMP\DeepSeek_Harness_Setup.exe"
    
    try {
        Write-Host "  Fetching installer from $downloadUrl..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
        Write-Host "  Running installer..." -ForegroundColor Gray
        Start-Process -FilePath $installerPath -Wait
        Start-Sleep -Seconds 3
    } catch {
        Write-Warning "Could not automatically download DeepSeek Harness ($($_.Exception.Message))."
        Write-Host "Please download and install DeepSeek Harness from https://deepseek.com/" -ForegroundColor Cyan
        Write-Host "Press Enter once installed to continue..."
        [void][System.Console]::ReadLine()
    }

    if (-not (Test-Path $dshExePath)) {
        Write-Warning "DeepSeek Harness executable still not detected. Setup will continue configuring the profile."
    }
}

# 3. BUILD MEMORY PLUGIN FROM SOURCE
Write-Host "`n[3/6] Building Evergreen Memory Plugin from source..." -ForegroundColor Yellow
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$pluginSourceDir = Join-Path $scriptDir "plugins\dsh-memory-plugin"
if (-not (Test-Path $pluginSourceDir)) {
    Write-Host "  Submodule not found. Initializing git submodule..." -ForegroundColor Gray
    git submodule update --init --recursive
}

$buildScript = Join-Path $pluginSourceDir "scripts\build-dist.mjs"
if (-not (Test-Path $buildScript)) {
    Write-Host "  ✗ Build script missing at $buildScript" -ForegroundColor Red
    exit 1
}

Write-Host "  Running zero-dependency transpiler ($buildScript)..." -ForegroundColor Gray
node $buildScript
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Plugin built successfully (bundled self-contained dist/core)" -ForegroundColor Green

# 4. PROVISION DSH PERMANENT STORAGE & PROFILE
Write-Host "`n[4/6] Provisioning DSH desktop profile & templates..." -ForegroundColor Yellow
$dshHome = Join-Path $env:USERPROFILE ".dsh"
$permanentPluginSrc = Join-Path $dshHome "plugins-src\dsh-memory-plugin"
$profileDesktop = Join-Path $dshHome "profiles\desktop"
$profileNodeModules = Join-Path $profileDesktop "node_modules\@evergreen-realm"
$junctionTarget = Join-Path $permanentPluginSrc "packages\dsh-memory"
$junctionPath = Join-Path $profileNodeModules "dsh-memory-plugin"

# Copy plugin to permanent location inside ~/.dsh/plugins-src/
New-Item -ItemType Directory -Force -Path (Split-Path $permanentPluginSrc -Parent) | Out-Null
if (-not (Test-Path $permanentPluginSrc)) {
    Write-Host "  Copying plugin to persistent home ($permanentPluginSrc)..." -ForegroundColor Gray
    Copy-Item -Recurse -Force -Path $pluginSourceDir -Destination $permanentPluginSrc
} else {
    Write-Host "  Updating persistent plugin files at $permanentPluginSrc..." -ForegroundColor Gray
    Copy-Item -Recurse -Force -Path "$pluginSourceDir\packages" -Destination "$permanentPluginSrc\"
    Copy-Item -Recurse -Force -Path "$pluginSourceDir\scripts" -Destination "$permanentPluginSrc\"
}

# Create profile directories
New-Item -ItemType Directory -Force -Path $profileDesktop | Out-Null
New-Item -ItemType Directory -Force -Path $profileNodeModules | Out-Null

# Resolve package.json template
$templatePath = Join-Path $scriptDir "profile-templates\package.json.template"
$resolvedPkgJson = (Get-Content $templatePath -Raw).Replace("{{PLUGIN_PATH}}", $junctionTarget.Replace('\', '/'))
Set-Content -Path (Join-Path $profileDesktop "package.json") -Value $resolvedPkgJson -NoNewline
Write-Host "  ✓ Generated ~/.dsh/profiles/desktop/package.json" -ForegroundColor Green

# Copy static profile templates
Copy-Item -Force -Path (Join-Path $scriptDir "profile-templates\cordis.yml") -Destination $profileDesktop
Copy-Item -Force -Path (Join-Path $scriptDir "profile-templates\cordis.patch.yml") -Destination $profileDesktop
Copy-Item -Force -Path (Join-Path $scriptDir "profile-templates\pnpm-workspace.yaml") -Destination $profileDesktop
Write-Host "  ✓ Applied cordis.patch.yml, cordis.yml, and pnpm-workspace.yaml" -ForegroundColor Green

# Recreate junction
if (Test-Path $junctionPath) {
    cmd /c "rmdir `"$junctionPath`"" 2>$null
    if (Test-Path $junctionPath) { Remove-Item -Recurse -Force $junctionPath -ErrorAction SilentlyContinue }
}
cmd /c "mklink /J `"$junctionPath`" `"$junctionTarget`"" | Out-Null
Write-Host "  ✓ Created permanent Junction: $junctionPath -> $junctionTarget" -ForegroundColor Green

# Install sanitizer tool into ~/.dsh/scripts/
$dshScriptsDir = Join-Path $dshHome "scripts"
New-Item -ItemType Directory -Force -Path $dshScriptsDir | Out-Null
$sanitizerRepoSrc = Join-Path $scriptDir "scripts\dsh-session-sanitizer.py"
$sanitizerDest = Join-Path $dshScriptsDir "dsh-session-sanitizer.py"
if (Test-Path $sanitizerRepoSrc) {
    Copy-Item -Force -Path $sanitizerRepoSrc -Destination $sanitizerDest
    Write-Host "  ✓ Installed session sanitizer tool to $sanitizerDest" -ForegroundColor Green
}

# 5. ENVIRONMENT VARIABLES (OLLAMA / MODEL CONFIG)
Write-Host "`n[5/6] Configuring API keys & model fallbacks..." -ForegroundColor Yellow
if (-not $OllamaKey) {
    $existingKey = [System.Environment]::GetEnvironmentVariable("OLLAMA_API_KEY", "User")
    if ($existingKey) {
        Write-Host "  ✓ Detected existing OLLAMA_API_KEY in User environment." -ForegroundColor Green
    } else {
        Write-Host "  Optional: You can provide an Ollama Cloud Pro API key for fallback models." -ForegroundColor Cyan
        Write-Host "  (Press Enter to skip if you only plan to use your DeepSeek account)" -ForegroundColor Gray
        $inputKey = Read-Host "  Enter OLLAMA_API_KEY"
        if ($inputKey -and $inputKey.Trim()) {
            [System.Environment]::SetEnvironmentVariable("OLLAMA_API_KEY", $inputKey.Trim(), "User")
            $env:OLLAMA_API_KEY = $inputKey.Trim()
            Write-Host "  ✓ OLLAMA_API_KEY saved to User environment." -ForegroundColor Green
        } else {
            Write-Host "  → Skipped Ollama key. DeepSeek Account will serve as primary." -ForegroundColor Gray
        }
    }
} else {
    [System.Environment]::SetEnvironmentVariable("OLLAMA_API_KEY", $OllamaKey.Trim(), "User")
    $env:OLLAMA_API_KEY = $OllamaKey.Trim()
    Write-Host "  ✓ OLLAMA_API_KEY configured." -ForegroundColor Green
}

# 6. COMPLETION & LAUNCH
Write-Host "`n[6/6] Finalizing setup..." -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   Setup Completed Successfully!                         " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Key paths:" -ForegroundColor Gray
Write-Host "  • DSH Profile: $profileDesktop"
Write-Host "  • Memory Plugin: $permanentPluginSrc"
Write-Host "  • Sanitizer: $dshScriptsDir\dsh-session-sanitizer.py"
Write-Host ""

if (-not $SkipLaunch -and (Test-Path $dshExePath)) {
    Write-Host "Launching DeepSeek Harness..." -ForegroundColor Cyan
    Start-Process -FilePath $dshExePath
} else {
    Write-Host "You can now start DeepSeek Harness whenever you're ready." -ForegroundColor Cyan
}
