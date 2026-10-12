# # Get user input path
Write-Host "Please enter the installation path and press Enter to confirm. If you leave it blank and press Enter, the current path will be used."
$userInputPath = Read-Host "Installation path"
$path = if ([string]::IsNullOrWhiteSpace($userInputPath)) {
    Get-Location
} else {
    $userInputPath
}
$path = $path.Path.Replace('\', '\\')
Write-Host "The installation path is: $path"
Write-Host "Initialising MySQL, please wait..."
Write-Host "Processing configuration information..."
try{
# # Replace the path configuration in my.ini (supports cross-drive paths)
$content = Get-Content "$path\my.ini" -Raw
# Match paths in a single file
$content = $content -replace '[A-Za-z]:\\+mysql8', "$path"
Set-Content "$path\my.ini" -Value $content -Force -Encoding Default
}catch{
    Write-Error "Failed to set configuration information: $($_.Exception.Message)"
    exit 1
}

# # Initialise the database and capture the temporary password
$log = & "$path\bin\mysqld.exe" --initialize --console 2>&1 | Out-String -Width 9999
# # Save the initialisation log to a file
$log | Out-File -FilePath "$path\initialize.log"

# # Extract the temporary password (compatible with MySQL 5.7+ versions)
$content = Get-Content "initialize.log" -Raw
$temporary = $log.Substring($log.LastIndexOf(":") + 2)
$temporary | Set-Clipboard
Write-Host ('Initialisation complete. The temporary password is: {0}' -f ($temporary))
Write-Host "Installing the service, please wait..."
# # Install the MySQL service (compatible with Windows systems)
try{
    & "$path\bin\mysqld.exe" --install MySQL | Tee-Object -FilePath "$path\initialize.log" -Append
    Write-Host "Service installed successfully. Log has been recorded."
}catch{
    Write-Error "Service installation failed: $($_.Exception.Message)"
    exit 1
}
# # Start the MySQL service and record the log
try {
    & "net" start "mysql" 2>&1 | Tee-Object -FilePath "$path\initialize.log" -Append
    Write-Host "Service started successfully. Log has been recorded."
} catch {
    Write-Error "Service start failed: $($_.Exception.Message)"
    exit 1
}
Write-Host "When you see the prompt for the password, right-click to paste the password."
& "$path\bin\mysql.exe" -u root -p
Read-Host -Prompt "Press Enter to exit..."