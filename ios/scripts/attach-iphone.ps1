# Passes the USB-connected iPhone through to WSL with usbipd-win.
# The first run must be from an elevated PowerShell (bind needs admin); later runs don't.
$ErrorActionPreference = 'Stop'

if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    Write-Host 'usbipd fehlt. Installieren mit:  winget install --exact dorssel.usbipd-win  (danach Terminal neu öffnen)'
    exit 1
}

$line = usbipd list | Select-String -Pattern '^\s*(\d+-\d+)\s+05ac:\S+\s+(.*?)\s{2,}(\S.*)$' | Select-Object -First 1
if (-not $line) {
    Write-Host 'Kein Apple-Gerät gefunden. iPhone per USB anschließen und entsperren.'
    exit 1
}
$busId = $line.Matches[0].Groups[1].Value
$state = $line.Matches[0].Groups[3].Value
Write-Host "iPhone auf Bus $busId ($state)"

if ($state -match 'Not shared') {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host 'Einmalig als Administrator ausführen, um das Gerät freizugeben (usbipd bind).'
        exit 1
    }
    usbipd bind --busid $busId
}
if ($state -notmatch 'Attached') {
    usbipd attach --wsl --busid $busId
}
Write-Host 'iPhone ist in WSL verfügbar. Prüfen mit:  wsl -- ideviceinfo -k DeviceName'
