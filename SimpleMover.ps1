<#
.SYNOPSIS
    Einfaches Datei-Management-Tool zum Verschieben von Dateien zwischen Ordnern.

.DESCRIPTION
    Dieses PowerShell-Skript ermöglicht es Benutzern, Dateien von einem Quellordner in einen Zielordner zu verschieben.
    Features:
    - Interaktive Benutzerführung
    - Automatische Auflistung verfügbarer Dateien
    - Einzelne oder Mehrfachauswahl von Dateien
    - Automatische Ordnererstellung bei Bedarf
    - Visuelle Statusanzeige für jeden Vorgang
    - Integrierte Fehlerbehandlung

.PARAMETER Keine
    Das Skript arbeitet interaktiv und benötigt keine Parameter.

.EXAMPLE
    PS> .\SimpleMover.ps1
    Startet den interaktiven Prozess zum Verschieben von Dateien.

.EXAMPLE
    PS> .\SimpleMover.ps1
    Quellpfad: C:\Temp
    Dateien auswählen: 1,3
    Zielpfad: D:\Archiv

.LINK
    https://github.com/chris-20/SimpleMover

.NOTES
    Dateiname: SimpleMover.ps1
    Voraussetzungen: Windows PowerShell 5.1 oder neuer
    Lizenz: MIT
    Version: 1.0
#>

Clear-Host
Write-Host "=== Einfaches Datei-Management ===" -ForegroundColor Cyan

# Quellpfad eingeben
do {
    $sourcePath = Read-Host "`nQuellpfad eingeben (wo sind die Dateien?)"
} while (-not $sourcePath)

# Prüfen ob Quellpfad existiert
if (-not (Test-Path $sourcePath)) {
    Write-Host "Ordner existiert nicht!" -ForegroundColor Red
    $create = Read-Host "Ordner erstellen? (J/N)"
    if ($create -eq 'J') {
        New-Item -ItemType Directory -Path $sourcePath
    } else {
        Write-Host "Programm wird beendet..." -ForegroundColor Yellow
        exit
    }
}

# Dateien im Quellordner anzeigen
Write-Host "`nGefundene Dateien:" -ForegroundColor Green
$files = Get-ChildItem $sourcePath
$i = 1
foreach ($file in $files) {
    Write-Host "$i. $($file.Name)"
    $i++
}

# Dateiauswahl
Write-Host "`nDateiauswahl:"
Write-Host "- Nummern eingeben (z.B. 1,3,4)"
Write-Host "- 'alle' für alle Dateien"
$selection = Read-Host "Auswahl"

if ($selection -eq 'alle') {
    $selectedFiles = $files.Name
} else {
    $selected = $selection.Split(',') | ForEach-Object { $_.Trim() }
    $selectedFiles = @()
    foreach ($num in $selected) {
        if ([int]$num -le $files.Count) {
            $selectedFiles += $files[$num - 1].Name
        }
    }
}

# Zielort eingeben
$destinationPath = Read-Host "`nZielpfad eingeben (wohin sollen die Dateien?)"
if (-not (Test-Path $destinationPath)) {
    Write-Host "Zielordner existiert nicht!" -ForegroundColor Yellow
    $create = Read-Host "Ordner erstellen? (J/N)"
    if ($create -eq 'J') {
        New-Item -ItemType Directory -Path $destinationPath
    } else {
        Write-Host "Programm wird beendet..." -ForegroundColor Yellow
        exit
    }
}

# Dateien verschieben
Write-Host "`nVerschiebe Dateien..." -ForegroundColor Cyan
foreach ($file in $selectedFiles) {
    $sourceFile = Join-Path -Path $sourcePath -ChildPath $file
    $destinationFile = Join-Path -Path $destinationPath -ChildPath $file
    
    try {
        Move-Item -Path $sourceFile -Destination $destinationFile -ErrorAction Stop
        Write-Host "✓ $file" -ForegroundColor Green
    } catch {
        Write-Host "✗ Fehler bei $file" -ForegroundColor Red
    }
}

Write-Host "`nFertig!" -ForegroundColor Green
Pause