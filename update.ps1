<#
  update.ps1 — Peft Logbook OTA release script
  ───────────────────────────────────────────────────────────────────────
  Run this from the project root every time you want to push a JS-only
  update to installed apps without going through the app stores.

  What it does:
    1. Reads APP_VERSION and the matching CHANGELOG entry out of www/index.html
    2. Zips www/ into bundles/peft-<version>.zip (Capgo bundle format —
       index.html must sit at the ROOT of the zip)
    3. Writes/updates latest.json with the new version, bundle URL and notes
    4. Commits + pushes both to the ue-peft-logbook GitHub repo
    5. Runs `npx cap sync` so a native rebuild (if you also need one) picks
       up the same web assets

  This does NOT rebuild the APK/AAB or IPA — that's only needed when you add
  or change a native plugin. For everyday JS/HTML/CSS changes, this script
  is the entire release process: push it, and installed apps pick it up the
  next time they're opened (checked on launch and on resume).

  Prereqs: git remote 'origin' already pointing at the ue-peft-logbook repo,
  and you're already authenticated (gh auth login or a credential helper).
  ───────────────────────────────────────────────────────────────────────
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$indexPath = Join-Path $root 'www\index.html'
if (-not (Test-Path $indexPath)) {
    throw "www/index.html not found. Copy the built Peft_v*.html there first (as index.html)."
}
$html = Get-Content $indexPath -Raw

# ── Pull APP_VERSION out of the HTML ──────────────────────────────────────
if ($html -notmatch "const APP_VERSION = '([^']+)'") {
    throw "Could not find APP_VERSION in www/index.html"
}
$version = $Matches[1]                     # e.g. v9.8
$versionBare = $version -replace '^v', ''  # e.g. 9.8  (used in filenames)
Write-Host "Releasing Peft Logbook $version..." -ForegroundColor Cyan

# ── Pull the matching CHANGELOG entry (best-effort; used for latest.json notes) ──
$notes = @()
if ($html -match [regex]::Escape("`"$version`": [") ) {
    # crude but sufficient: grab the array literal for this version key
    $pattern = [regex]::Escape("`"$version`":") + '\s*\[(.*?)\]'
    $m = [regex]::Match($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($m.Success) {
        $items = [regex]::Matches($m.Groups[1].Value, '"((?:[^"\\]|\\.)*)"')
        foreach ($it in $items) { $notes += ($it.Groups[1].Value -replace '\\"','"') }
    }
}
if ($notes.Count -eq 0) { Write-Host "  (no CHANGELOG entry found for $version — latest.json will ship with empty notes)" -ForegroundColor Yellow }

# ── Zip the web bundle (index.html must be at the zip ROOT for Capgo) ────
$bundlesDir = Join-Path $root 'bundles'
New-Item -ItemType Directory -Force -Path $bundlesDir | Out-Null
$zipName = "peft-$versionBare.zip"
$zipPath = Join-Path $bundlesDir $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath }
Compress-Archive -Path (Join-Path $root 'www\*') -DestinationPath $zipPath -CompressionLevel Optimal
Write-Host "  Bundle written: bundles/$zipName" -ForegroundColor Green

# ── Write latest.json ─────────────────────────────────────────────────────
$repoRawBase = "https://raw.githubusercontent.com/storemybits-ui/ue-peft-logbook/main"
$manifest = [ordered]@{
    version = $version
    url     = "$repoRawBase/bundles/$zipName"
    notes   = $notes
}
$manifestPath = Join-Path $root 'latest.json'
($manifest | ConvertTo-Json -Depth 5) | Set-Content -Path $manifestPath -Encoding utf8
Write-Host "  latest.json updated -> version $version" -ForegroundColor Green

# ── npx cap sync (keeps the native shells' bundled copy in step, in case you
#    also do a store build later) ──────────────────────────────────────────
if (Get-Command npx -ErrorAction SilentlyContinue) {
    Write-Host "  Running npx cap sync..." -ForegroundColor Cyan
    npx cap sync
} else {
    Write-Host "  Skipping cap sync (npx not found on PATH)" -ForegroundColor Yellow
}

# ── Commit + push ─────────────────────────────────────────────────────────
git add latest.json "bundles/$zipName"
git commit -m "Release $version"
git push origin main

Write-Host ""
Write-Host "Done. Installed apps will pick up $version next time they're opened." -ForegroundColor Cyan
Write-Host "(Checked ~1.5s after launch, and again whenever the app returns to the foreground.)"
