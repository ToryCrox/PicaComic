# PowerShell script for building and copying Windows application
# Usage: .\build_win.ps1

Write-Host "========================================" -ForegroundColor Cyan
$startTime = Get-Date
Write-Host "Script started at $($startTime.ToString('yyyy/MM/dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Building Windows application..." -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Build the application
$buildResult = & flutter build windows
$buildExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Flutter build command completed!" -ForegroundColor Cyan
Write-Host "Debug: Exit code = $buildExitCode" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($buildExitCode -ne 0) {
    Write-Host "WARNING: Flutter build returned exit code $buildExitCode" -ForegroundColor Yellow
    Write-Host "Continuing anyway to attempt file copy..." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Build step completed! Proceeding to file copy..." -ForegroundColor Green
Write-Host ""

# Wait a moment to ensure files are fully written
Write-Host "Waiting for file system to sync..." -ForegroundColor Gray
Start-Sleep -Seconds 2

# Define source and destination directories
$sourceDir = "E:\Workspace\flutter\PicaComic\build\windows\x64\runner\Release"
$destinationDir = "E:\Program Files\PicaComic"

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Preparing to copy files..." -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Source: $sourceDir"
Write-Host "Destination: $destinationDir"
Write-Host ""

# Check if source directory exists
if (-not (Test-Path $sourceDir)) {
    Write-Host "ERROR: Source directory does not exist: $sourceDir" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "Source directory exists: OK" -ForegroundColor Green

# Create destination directory if it doesn't exist
if (-not (Test-Path $destinationDir)) {
    Write-Host "Creating destination directory..." -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        Write-Host "Destination directory created: OK" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to create destination directory!" -ForegroundColor Red
        Write-Host "This may require administrator privileges." -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
} else {
    Write-Host "Destination directory exists: OK" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Starting file copy..." -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Copy files
try {
    Copy-Item -Path "$sourceDir\*" -Destination $destinationDir -Recurse -Force -ErrorAction Stop
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Copy completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Files copied from:"
    Write-Host "  $sourceDir"
    Write-Host "To:"
    Write-Host "  $destinationDir"
    Write-Host ""
} catch {
    Write-Host ""
    Write-Host "ERROR: Copy failed!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
$endTime = Get-Date
$elapsed = $endTime - $startTime
Write-Host "Script completed at $($endTime.ToString('yyyy/MM/dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "Total time elapsed: $($elapsed.Minutes)m $($elapsed.Seconds)s" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

