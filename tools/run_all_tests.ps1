# Run all X-Ray plugin unit tests in WSL
Write-Host "Starting X-Ray Plugin Test Suite..." -ForegroundColor Cyan

$tests = @(
    "spec/xray_utils_spec.lua",
    "spec/xray_chapteranalyzer_spec.lua",
    "spec/xray_fetch_spec.lua",
    "spec/xray_cachemanager_spec.lua",
    "spec/xray_aihelper_spec.lua",
    "spec/xray_data_spec.lua",
    "spec/xray_lookupmanager_spec.lua",
    "spec/xray_ui_spec.lua"
)

$all_passed = $true

foreach ($test in $tests) {
    Write-Host "`nRunning $test..." -ForegroundColor Yellow
    wsl busted $test
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $test" -ForegroundColor Red
        $all_passed = $false
    } else {
        Write-Host "PASSED: $test" -ForegroundColor Green
    }
}

Write-Host "`n----------------------------------------"
if ($all_passed) {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green -BackgroundColor Black
} else {
    Write-Host "SOME TESTS FAILED!" -ForegroundColor Red -BackgroundColor Black
    exit 1
}
