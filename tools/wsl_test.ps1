param (
    [switch]$Watch
)

$PluginDir = "xray.koplugin"
$WSLDest = "~/.config/koreader/plugins/xray.koplugin"
$SyntaxScript = "tools/check_syntax.py"

function Run-Workflow {
    Write-Host "`n--- Starting Verification Workflow ---" -ForegroundColor Cyan
    
    # 1. Syntax Check
    Write-Host "Checking Lua syntax..." -NoNewline
    $syntaxResult = python $SyntaxScript $PluginDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host $syntaxResult
        return $false
    }
    Write-Host " PASSED" -ForegroundColor Green

    # 2. Unit Tests
    Write-Host "Running unit tests (Busted in WSL)..."
    wsl busted spec/
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Tests FAILED. Aborting sync." -ForegroundColor Red
        return $false
    }
    Write-Host "Tests PASSED" -ForegroundColor Green

    # 3. Sync
    Write-Host "Syncing to WSL..." -NoNewline
    wsl mkdir -p (Split-Path $WSLDest -Parent)
    
    # Smart Config Merge (mimics xray_updater.lua)
    # 1. Backup existing keys if file exists
    $ConfigSubPath = "xray_config.lua"
    $BackupPath = "/tmp/xray_config_backup.lua"
    wsl sh -c "if [ -f $WSLDest/$ConfigSubPath ]; then cp $WSLDest/$ConfigSubPath $BackupPath; fi"

    # 2. Sync (this will overwrite xray_config.lua with the one from Windows)
    wsl rsync -rv --delete "./$PluginDir/" "$WSLDest/"
    
    # 3. Restore keys from backup
    $MergeScript = "tools/merge_config.py"
    wsl python3 "/mnt/c/Users/jpautz/Documents/ko/koreader-xray-plugin/$MergeScript" "$WSLDest/$ConfigSubPath" "$BackupPath"
    wsl rm -f "$BackupPath"

    if ($LASTEXITCODE -ne 0) {
        Write-Host " FAILED" -ForegroundColor Red
        return $false
    }
    Write-Host " SUCCESS" -ForegroundColor Green

    # 4. Restart KOReader
    Write-Host "Restarting KOReader..." -ForegroundColor Cyan
    wsl pkill -9 -f koreader 2>$null
    wsl pkill -9 -f AppRun 2>$null
    Start-Sleep -Seconds 1

    $StartCmd = if ($env:KOREADER_START_CMD) { $env:KOREADER_START_CMD } else { 'wsl /mnt/c/Users/jpautz/squashfs-root/AppRun' }
    Write-Host "Starting KOReader: $StartCmd"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -Command `"$StartCmd`""
        $psi.UseShellExecute = $true
        $psi.WindowStyle = "Normal"
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        Write-Host "Restart command sent successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to start KOReader: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`nReady!" -ForegroundColor Green
    return $true
}

if ($Watch) {
    Write-Host "Watching for changes in $PluginDir..." -ForegroundColor Magenta
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = (Get-Item "./$PluginDir").FullName
    $watcher.Filter = "*.lua"
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true

    $action = {
        Run-Workflow
    }

    Register-ObjectEvent $watcher "Changed" -Action $action
    Register-ObjectEvent $watcher "Created" -Action $action
    Register-ObjectEvent $watcher "Deleted" -Action $action
    Register-ObjectEvent $watcher "Renamed" -Action $action

    while ($true) { Start-Sleep -Seconds 1 }
} else {
    Run-Workflow
}
