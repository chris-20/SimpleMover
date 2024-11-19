<#
.SYNOPSIS
    Modern File Management Tool mit Vorschau und Backup
.DESCRIPTION
    Professionelles PowerShell-Skript für intelligentes Dateimanagement.
    Features: 
    - Vorschau-Modus für geplante Änderungen
    - Automatisches Backup-System
    - Dateinamensbereinigung
    - Umlautkonvertierung
    - Detaillierte Statusanzeigen
    - Intelligente Dateiauswahl
    - Fehlerbehandlung und Logging
.NOTES
    Version: 1.2
    Updated: 2024
#>

#Region Parameters
param(
    [Parameter(Mandatory=$false)]
    [Alias('src')]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$false)]
    [Alias('dst')]
    [string]$DestinationPath,
    
    [Parameter(Mandatory=$false)]
    [Alias('f')]
    [string]$FilePattern = "*",
    
    [Parameter(Mandatory=$false)]
    [Alias('c')]
    [switch]$CleanFileNames,
    
    [Parameter(Mandatory=$false)]
    [Alias('u')]
    [switch]$ReplaceUmlauts,
    
    [Parameter(Mandatory=$false)]
    [Alias('s')]
    [switch]$RemoveSpaces,
    
    [Parameter(Mandatory=$false)]
    [Alias('sc')]
    [switch]$RemoveSpecialChars,
    
    [Parameter(Mandatory=$false)]
    [Alias('p')]
    [switch]$Preview,

    [Parameter(Mandatory=$false)]
    [Alias('b')]
    [switch]$CreateBackup,
    
    [Parameter(Mandatory=$false)]
    [switch]$RestoreLatestBackup,
    
    [Parameter(Mandatory=$false)]
    [switch]$ListBackups,
    
    [Parameter(Mandatory=$false)]
    [int]$KeepBackupDays = 7,

    [Parameter(Mandatory=$false)]
    [switch]$EnableLogging
)
#EndRegion Parameters

#Region Classes
class Logger {
    static [string] $LogPath = ".\FileManager_Logs"
    static [string] $CurrentLogFile

    static Logger() {
        [Logger]::CurrentLogFile = Join-Path ([Logger]::LogPath) ("Log_" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + ".txt")
        if (-not (Test-Path ([Logger]::LogPath))) {
            New-Item -ItemType Directory -Path ([Logger]::LogPath) | Out-Null
        }
    }

    static [void] Log([string]$message, [string]$level = "INFO") {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$level] $message"
        Add-Content -Path ([Logger]::CurrentLogFile) -Value $logMessage
        
        switch ($level) {
            "ERROR" { Write-Host $logMessage -ForegroundColor Red }
            "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
            "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
            default { Write-Host $logMessage -ForegroundColor Gray }
        }
    }
}

class FileNameCleaner {
    static [string] Clean([string]$fileName, [bool]$umlauts, [bool]$spaces, [bool]$specialChars) {
        if ([string]::IsNullOrEmpty($fileName)) {
            throw "Dateiname darf nicht leer sein."
        }

        $result = $fileName

        if ($umlauts) {
            $result = $result.Replace("ä", "ae").Replace("ö", "oe").Replace("ü", "ue")
            $result = $result.Replace("Ä", "Ae").Replace("Ö", "Oe").Replace("Ü", "Ue")
            $result = $result.Replace("ß", "ss")
        }
        
        if ($spaces) {
            $result = $result.Replace(" ", "_")
        }
        
        if ($specialChars) {
            $result = [RegEx]::Replace($result, '[^a-zA-Z0-9._-]', '')
        }

        # Ensure filename is still valid after cleaning
        if ([string]::IsNullOrEmpty($result) -or $result -match '^\.+$') {
            throw "Ungültiger Dateiname nach Bereinigung: $fileName"
        }
        
        return $result
    }
}

class FileSelector {
    static [array] SelectFiles([string]$path) {
        if (-not (Test-Path $path)) {
            [Logger]::Log("Pfad nicht gefunden: $path", "ERROR")
            return @()
        }

        $files = Get-ChildItem -Path $path
        if ($files.Count -eq 0) {
            [Logger]::Log("Keine Dateien im angegebenen Pfad gefunden: $path", "WARNING")
            return @()
        }

        Write-Host "`n📁 Verfügbare Dateien:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $files.Count; $i++) {
            $fileSize = [math]::Round($files[$i].Length / 1MB, 2)
            Write-Host "  [$($i + 1)] $($files[$i].Name) ($fileSize MB)" -ForegroundColor Yellow
            
            if ($i -gt 0 -and ($i + 1) % 20 -eq 0 -and $i -lt $files.Count - 1) {
                Write-Host "  Drücken Sie eine Taste für weitere Dateien..." -ForegroundColor Gray
                [Console]::ReadKey($true) | Out-Null
            }
        }

        Write-Host "`n📝 Dateien auswählen:" -ForegroundColor Cyan
        Write-Host "  • 'alle' - Alle Dateien auswählen" -ForegroundColor Gray
        Write-Host "  • '1,3,4' - Einzelne Dateien auswählen" -ForegroundColor Gray
        Write-Host "  • '1-5' - Bereich auswählen" -ForegroundColor Gray
        Write-Host "  • '*.txt' - Nach Muster auswählen" -ForegroundColor Gray
        Write-Host "  • 'q' - Beenden" -ForegroundColor Gray
        
        while ($true) {
            $selection = Read-Host "`nAuswahl"
            
            if ($selection.ToLower() -eq 'q') {
                return @()
            }
            
            if ($selection.ToLower() -eq 'alle') {
                [Logger]::Log("Alle Dateien ausgewählt", "INFO")
                return $files
            }

            # Pattern-basierte Auswahl
            if ($selection.Contains("*")) {
                $selectedFiles = $files | Where-Object { $_.Name -like $selection }
                if ($selectedFiles.Count -gt 0) {
                    [Logger]::Log("$($selectedFiles.Count) Dateien nach Muster '$selection' ausgewählt", "INFO")
                    return $selectedFiles
                }
                Write-Host "❌ Keine Dateien gefunden, die dem Muster entsprechen." -ForegroundColor Red
                continue
            }

            # Bereichsauswahl
            if ($selection -match '^\d+-\d+$') {
                $range = $selection -split '-' | ForEach-Object { [int]$_ }
                if ($range[0] -le $range[1] -and $range[0] -ge 1 -and $range[1] -le $files.Count) {
                    $selectedFiles = $files[($range[0]-1)..($range[1]-1)]
                    [Logger]::Log("$($selectedFiles.Count) Dateien im Bereich $($range[0])-$($range[1]) ausgewählt", "INFO")
                    return $selectedFiles
                }
                Write-Host "❌ Ungültiger Bereich. Bitte geben Sie einen gültigen Bereich ein." -ForegroundColor Red
                continue
            }
            
            # Einzelauswahl
            try {
                $selectedIndices = $selection -split ',' | 
                                  Where-Object { $_ -match '^\s*\d+\s*$' } |
                                  ForEach-Object { [int]$_.Trim() - 1 }
                
                $selectedFiles = $selectedIndices | 
                               Where-Object { $_ -ge 0 -and $_ -lt $files.Count } |
                               ForEach-Object { $files[$_] }
                
                if ($selectedFiles.Count -gt 0) {
                    Write-Host "`n✓ Ausgewählte Dateien:" -ForegroundColor Green
                    $selectedFiles | ForEach-Object {
                        $fileSize = [math]::Round($_.Length / 1MB, 2)
                        Write-Host "  • $($_.Name) ($fileSize MB)" -ForegroundColor Yellow
                    }
                    [Logger]::Log("$($selectedFiles.Count) Dateien manuell ausgewählt", "INFO")
                    return $selectedFiles
                }
            }
            catch {
                [Logger]::Log("Fehler bei der Dateiauswahl: $($_.Exception.Message)", "ERROR")
            }
            
            Write-Host "❌ Ungültige Auswahl. Bitte versuchen Sie es erneut." -ForegroundColor Red
        }

        # Dieser Code wird nie erreicht, aber PowerShell erfordert einen expliziten Return-Pfad
        return @()
    }
}

class BackupManager {
    static [string] $BackupRoot = ".\FileManager_Backups"
    
    static [string] CreateBackup([string]$sourcePath) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $backupName = "Backup_$timestamp"
        $backupPath = Join-Path ([BackupManager]::BackupRoot) $backupName
        
        Write-Host "`n╔════════════════ Backup ════════════════╗" -ForegroundColor Blue
        Write-Host "  Erstelle Backup: $backupName" -ForegroundColor Yellow
        
        try {
            if (-not (Test-Path ([BackupManager]::BackupRoot))) {
                New-Item -ItemType Directory -Path ([BackupManager]::BackupRoot) | Out-Null
            }
            
            New-Item -ItemType Directory -Path $backupPath | Out-Null
            
            $files = Get-ChildItem -Path $sourcePath
            $totalFiles = $files.Count
            $currentFile = 0
            $totalSize = 0
            
            foreach ($file in $files) {
                $currentFile++
                $percent = [math]::Round(($currentFile / $totalFiles) * 100)
                $totalSize += $file.Length
                
                Write-Progress -Activity "Erstelle Backup" `
                             -Status "$percent% Complete" `
                             -PercentComplete $percent `
                             -CurrentOperation $file.Name
                
                Copy-Item -Path $file.FullName -Destination $backupPath -ErrorAction Stop
            }
            
            $infoPath = Join-Path $backupPath "backup_info.json"
            $backupInfo = @{
                SourcePath = $sourcePath
                CreatedAt = $timestamp
                FileCount = $totalFiles
                TotalSize = $totalSize
            } | ConvertTo-Json
            
            Set-Content -Path $infoPath -Value $backupInfo
            
            [Logger]::Log("Backup erstellt: $backupName mit $totalFiles Dateien", "SUCCESS")
            Write-Host "  ✓ Backup erstellt: $($files.Count) Dateien" -ForegroundColor Green
            Write-Host "  📂 Speicherort: $backupPath" -ForegroundColor Yellow
            Write-Host "╚═════════════════════════════════════╝`n" -ForegroundColor Blue
            
            return $backupPath
        }
        catch {
            [Logger]::Log("Backup fehlgeschlagen: $($_.Exception.Message)", "ERROR")
            Write-Host "  ✗ Backup fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "╚═════════════════════════════════════╝`n" -ForegroundColor Blue
            throw
        }
        finally {
            Write-Progress -Activity "Erstelle Backup" -Completed
        }
    }

    static [void] RestoreBackup([string]$backupPath, [string]$destinationPath) {
        if (-not (Test-Path $backupPath)) {
            throw "Backup nicht gefunden: $backupPath"
        }
        
        Write-Host "`n╔═══════════ Wiederherstellung ══════════╗" -ForegroundColor Magenta
        Write-Host "  Stelle Backup wieder her..." -ForegroundColor Yellow
        
        try {
            $infoPath = Join-Path $backupPath "backup_info.json"
            $backupInfo = Get-Content -Path $infoPath | ConvertFrom-Json
            
            $files = Get-ChildItem -Path $backupPath -Exclude "backup_info.json"
            $totalFiles = $files.Count
            $currentFile = 0
            
            foreach ($file in $files) {
                $currentFile++
                $percent = [math]::Round(($currentFile / $totalFiles) * 100)
                
                Write-Progress -Activity "Stelle Backup wieder her" `
                             -Status "$percent% Complete" `
                             -PercentComplete $percent `
                             -CurrentOperation $file.Name
                
                Copy-Item -Path $file.FullName -Destination $destinationPath -ErrorAction Stop
            }
            
            [Logger]::Log("Backup wiederhergestellt mit $totalFiles Dateien", "SUCCESS")
            Write-Host "  ✓ Wiederherstellung abgeschlossen" -ForegroundColor Green
            Write-Host "  📂 Wiederhergestellte Dateien: $totalFiles" -ForegroundColor Yellow
        }
        catch {
            [Logger]::Log("Wiederherstellung fehlgeschlagen: $($_.Exception.Message)", "ERROR")
            Write-Host "  ✗ Wiederherstellung fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
            throw
        }
        finally {
            Write-Host "╚═════════════════════════════════════╝`n" -ForegroundColor Magenta
            Write-Progress -Activity "Stelle Backup wieder her" -Completed
        }
    }
    
    static [void] ListBackups() {
        if (-not (Test-Path ([BackupManager]::BackupRoot))) {
            Write-Host "Keine Backups gefunden." -ForegroundColor Yellow
            return
        }
        
        Write-Host "`n=== Verfügbare Backups ===" -ForegroundColor Cyan
        $backups = Get-ChildItem -Path ([BackupManager]::BackupRoot) -Directory | Sort-Object CreationTime -Descending
        
        foreach ($backup in $backups) {
            $infoPath = Join-Path $backup.FullName "backup_info.json"
            if (Test-Path $infoPath) {
                $info = Get-Content -Path $infoPath | ConvertFrom-Json
                Write-Host "`nBackup: $($backup.Name)" -ForegroundColor Yellow
                Write-Host "  ├─ Erstellt: $($info.CreatedAt)"
                Write-Host "  ├─ Dateien: $($info.FileCount)"
                Write-Host "  ├─ Größe: $([math]::Round($info.TotalSize / 1MB, 2)) MB"
                Write-Host "  └─ Quellpfad: $($info.SourcePath)"
            }
        }
        Write-Host ""
    }
    
    static [void] CleanupOldBackups([int]$keepDays = 7) {
        if (-not (Test-Path ([BackupManager]::BackupRoot))) {
            return
        }
        
        $cutoffDate = (Get-Date).AddDays(-$keepDays)
        $oldBackups = Get-ChildItem -Path ([BackupManager]::BackupRoot) -Directory |
                     Where-Object { $_.CreationTime -lt $cutoffDate }
        
        foreach ($backup in $oldBackups) {
            Remove-Item -Path $backup.FullName -Recurse -Force
            [Logger]::Log("Altes Backup entfernt: $($backup.Name)", "INFO")
        }
    }
}

class PreviewManager {
    hidden static [string] $lastResponse = 'N'
    
    static [void] ShowHeader() {
        Write-Host "`n╔════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║           Vorschau-Modus           ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════╝`n" -ForegroundColor Cyan
    }

    static [bool] PreviewChanges(
        [array]$files,
        [bool]$clean,
        [bool]$umlauts,
        [bool]$spaces,
        [bool]$specialChars,
        [string]$destination
    ) {
        [PreviewManager]::ShowHeader()
        
        if ($files.Count -eq 0) {
            [Logger]::Log("Keine Dateien für Vorschau verfügbar", "WARNING")
            return $false
        }

        $changesFound = $false
        $totalSize = 0
        $affectedFiles = 0
        
        Write-Host "📂 Zielordner: $destination`n" -ForegroundColor Yellow
        Write-Host "Geplante Änderungen:" -ForegroundColor Green
        
        foreach ($file in $files) {
            $newName = $file.Name
            if ($clean) {
                try {
                    $newName = [FileNameCleaner]::Clean($newName, $umlauts, $spaces, $specialChars)
                }
                catch {
                    [Logger]::Log("Fehler beim Bereinigen von $($file.Name): $($_.Exception.Message)", "ERROR")
                    continue
                }
            }
            
            $totalSize += $file.Length
            if ($file.Name -ne $newName) {
                $affectedFiles++
                $changesFound = $true
                Write-Host "  ├─ Umbenennen:" -ForegroundColor Yellow
                Write-Host "  │  Von: $($file.Name)" -ForegroundColor Gray
                Write-Host "  │  Nach: $newName" -ForegroundColor White
            }
            else {
                Write-Host "  ├─ Unverändert: $($file.Name)" -ForegroundColor DarkGray
            }
        }
        
        Write-Host "`nZusammenfassung:" -ForegroundColor Cyan
        Write-Host "  ├─ Dateien gesamt: $($files.Count)"
        Write-Host "  ├─ Dateien betroffen: $affectedFiles"
        Write-Host "  ├─ Gesamtgröße: $([math]::Round($totalSize / 1MB, 2)) MB"
        Write-Host "  └─ Geschätzte Dauer: $([math]::Round($totalSize / 1MB / 10, 0)) Sekunden`n"
        
        if (-not $changesFound) {
            [Logger]::Log("Keine Änderungen notwendig", "INFO")
            Write-Host "ℹ️ Keine Änderungen notwendig!`n" -ForegroundColor Yellow
            return $true
        }
        
        do {
            Write-Host "Möchten Sie fortfahren? (J/N/D für Details)" -ForegroundColor Yellow
            [PreviewManager]::lastResponse = Read-Host
            
            if ([PreviewManager]::lastResponse -eq 'D') {
                [PreviewManager]::ShowDetailedPreview($files, $clean, $umlauts, $spaces, $specialChars)
            }
        } until ([PreviewManager]::lastResponse -eq 'J' -or [PreviewManager]::lastResponse -eq 'N')
        
        return [PreviewManager]::lastResponse -eq 'J'
    }
    
    static [void] ShowDetailedPreview(
        [array]$files,
        [bool]$clean,
        [bool]$umlauts,
        [bool]$spaces,
        [bool]$specialChars
    ) {
        Clear-Host
        Write-Host "`n=== Detaillierte Vorschau ===" -ForegroundColor Cyan
        
        $extensions = $files | Group-Object Extension
        Write-Host "`nDateitypen:" -ForegroundColor Yellow
        foreach ($ext in $extensions) {
            $extSize = ($ext.Group | Measure-Object Length -Sum).Sum
            Write-Host "  ├─ $($ext.Name): $($ext.Count) Dateien ($([math]::Round($extSize / 1MB, 2)) MB)"
        }
        
        Write-Host "`nGrößte Dateien:" -ForegroundColor Yellow
        $files | Sort-Object Length -Descending | Select-Object -First 5 | ForEach-Object {
            Write-Host "  ├─ $($_.Name) ($([math]::Round($_.Length / 1MB, 2)) MB)"
        }

        Write-Host "`nÄlteste Dateien:" -ForegroundColor Yellow
        $files | Sort-Object CreationTime | Select-Object -First 3 | ForEach-Object {
            Write-Host "  ├─ $($_.Name) (Erstellt: $($_.CreationTime))"
        }
        
        Write-Host "`nDrücken Sie eine Taste für die Rückkehr zur Vorschau..." -ForegroundColor Gray
        [System.Console]::ReadKey($true) | Out-Null
        Clear-Host
    }
}

class FileOperation {
    static [void] ProcessFiles(
        [string]$source,
        [string]$destination,
        [array]$selectedFiles,
        [bool]$clean,
        [bool]$umlauts,
        [bool]$spaces,
        [bool]$specialChars,
        [bool]$previewMode
    ) {
        [Console]::Clear()
        Write-Host "╔════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║      Modern File Management        ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════╝`n" -ForegroundColor Cyan
        
        if (-not [FileOperation]::ValidatePaths($source, $destination)) {
            return
        }
        
        if ($previewMode) {
            $proceed = [PreviewManager]::PreviewChanges(
                $selectedFiles, $clean, $umlauts, $spaces, $specialChars, $destination
            )
            if (-not $proceed) {
                [Logger]::Log("Operation durch Benutzer abgebrochen", "INFO")
                Write-Host "`n❌ Operation abgebrochen!" -ForegroundColor Yellow
                return
            }
        }
        
        $totalFiles = $selectedFiles.Count
        $currentFile = 0
        $successCount = 0
        $errorCount = 0
        
        foreach ($file in $selectedFiles) {
            $currentFile++
            $progressPercentage = [math]::Round(($currentFile / $totalFiles) * 100)
            
            Write-Progress -Activity "Verarbeite Dateien" `
                         -Status "$progressPercentage% Complete" `
                         -PercentComplete $progressPercentage `
                         -CurrentOperation $file.Name
            
            [string]$newName = $file.Name
            if ($clean) {
                try {
                    $newName = [FileNameCleaner]::Clean($newName, $umlauts, $spaces, $specialChars)
                }
                catch {
                    [Logger]::Log("Fehler beim Bereinigen von $($file.Name): $($_.Exception.Message)", "ERROR")
                    $errorCount++
                    continue
                }
            }
            
            try {
                [string]$destinationFile = Join-Path $destination $newName
                if (Test-Path $destinationFile) {
                    $i = 1
                    $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($newName)
                    $extension = [System.IO.Path]::GetExtension($newName)
                    while (Test-Path $destinationFile) {
                        $newName = "${fileNameWithoutExt}_${i}${extension}"
                        $destinationFile = Join-Path $destination $newName
                        $i++
                    }
                    [Logger]::Log("Datei existiert bereits, verwende alternativen Namen: $newName", "WARNING")
                }

                Copy-Item -Path $file.FullName -Destination $destinationFile -ErrorAction Stop
                $successCount++
                Write-Host "[$progressPercentage%] ✓ " -ForegroundColor Green -NoNewline
                Write-Host "$($file.Name) -> $newName"
                [Logger]::Log("Datei erfolgreich kopiert: $($file.Name) -> $newName", "SUCCESS")
            }
            catch {
                $errorCount++
                Write-Host "[$progressPercentage%] ✗ " -ForegroundColor Red -NoNewline
                Write-Host "$($file.Name): $($_.Exception.Message)"
                [Logger]::Log("Fehler beim Kopieren von $($file.Name): $($_.Exception.Message)", "ERROR")
            }
        }
        
        Write-Progress -Activity "Verarbeite Dateien" -Completed
        [FileOperation]::ShowSummary($successCount, $errorCount)
    }
    
    static [bool] ValidatePaths([string]$source, [string]$destination) {
        if (-not (Test-Path $source)) {
            [Logger]::Log("Quellordner nicht gefunden: $source", "ERROR")
            Write-Host "❌ Quellordner nicht gefunden: $source" -ForegroundColor Red
            return $false
        }
        
        if (-not (Test-Path $destination)) {
            [Logger]::Log("Erstelle Zielordner: $destination", "INFO")
            Write-Host "📁 Erstelle Zielordner: $destination" -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $destination | Out-Null
        }
        
        return $true
    }
    
    static [void] ShowSummary([int]$successCount, [int]$errorCount) {
        Write-Host "`n═══════════════ Zusammenfassung ═══════════════" -ForegroundColor Cyan
        Write-Host "📊 Erfolgreich verarbeitet: $successCount" -ForegroundColor Green
        if ($errorCount -gt 0) {
            Write-Host "❌ Fehler aufgetreten: $errorCount" -ForegroundColor Red
        }
        Write-Host "⏱️ Beendet: $(Get-Date -Format 'HH:mm:ss')"
        Write-Host "═════════════════════════════════════════════`n" -ForegroundColor Cyan
        
        [Logger]::Log("Verarbeitung abgeschlossen. Erfolge: $successCount, Fehler: $errorCount", "INFO")
    }
}

#Region Main
try {
    # Aktiviere Logging wenn gewünscht
    if ($EnableLogging) {
        # Logger wird automatisch initialisiert
        [Logger]::Log("Skript gestartet", "INFO")
    }

    if ($ListBackups) {
        [BackupManager]::ListBackups()
        exit 0
    }
    
    if ($RestoreLatestBackup) {
        $latestBackup = Get-ChildItem -Path ([BackupManager]::BackupRoot) -Directory |
                       Sort-Object CreationTime -Descending |
                       Select-Object -First 1
        if ($latestBackup) {
            [BackupManager]::RestoreBackup($latestBackup.FullName, $DestinationPath)
        }
        else {
            [Logger]::Log("Keine Backups gefunden", "WARNING")
            Write-Host "Keine Backups gefunden!" -ForegroundColor Red
        }
        exit 0
    }

    # Interaktiver Modus
    if (-not $SourcePath) {
        Write-Host "`n📂 Quellpfad Konfiguration" -ForegroundColor Yellow
        do {
            $SourcePath = Read-Host "Quellpfad eingeben"
            if (-not (Test-Path $SourcePath)) {
                Write-Host "❌ Pfad nicht gefunden. Bitte geben Sie einen gültigen Pfad ein." -ForegroundColor Red
            }
        } while (-not (Test-Path $SourcePath))
    }

    # Dateiauswahl
    $selectedFiles = [FileSelector]::SelectFiles($SourcePath)
    if ($selectedFiles.Count -eq 0) {
        [Logger]::Log("Keine Dateien ausgewählt, Programm wird beendet", "WARNING")
        Write-Host "❌ Keine Dateien ausgewählt. Beende Programm." -ForegroundColor Red
        exit 1
    }

    if (-not $DestinationPath) {
        Write-Host "`n📂 Zielpfad Konfiguration" -ForegroundColor Yellow
        $DestinationPath = Read-Host "Zielpfad eingeben"
        
        Write-Host "`n🛠️ Optionen" -ForegroundColor Yellow
        $cleanAnswer = Read-Host "Dateinamen bereinigen? (J/N)"
        if ($cleanAnswer -eq 'J') {
            $CleanFileNames = $true
            $ReplaceUmlauts = (Read-Host "  ├─ Umlaute ersetzen? (J/N)") -eq 'J'
            $RemoveSpaces = (Read-Host "  ├─ Leerzeichen entfernen? (J/N)") -eq 'J'
            $RemoveSpecialChars = (Read-Host "  └─ Sonderzeichen entfernen? (J/N)") -eq 'J'
        }
        
        $Preview = (Read-Host "`nVorschau vor der Ausführung anzeigen? (J/N)") -eq 'J'
        $CreateBackup = (Read-Host "Backup erstellen? (J/N)") -eq 'J'
    }

    # Alte Backups aufräumen
    [BackupManager]::CleanupOldBackups($KeepBackupDays)
    
    # Backup erstellen wenn gewünscht
    if ($CreateBackup) {
        $backupPath = [BackupManager]::CreateBackup($SourcePath)
    }

# Dateien verarbeiten
    [FileOperation]::ProcessFiles(
        $SourcePath,
        $DestinationPath,
        $selectedFiles,
        $CleanFileNames,
        $ReplaceUmlauts,
        $RemoveSpaces,
        $RemoveSpecialChars,
        $Preview
    )

    # Abschluss-Log
    if ($EnableLogging) {
        [Logger]::Log("Skript erfolgreich beendet", "SUCCESS")
    }
}
catch {
    [Logger]::Log("Kritischer Fehler: $($_.Exception.Message)", "ERROR")
    Write-Host "`n❌ Unerwarteter Fehler:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host "`nStacktrace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace
    exit 1
}
finally {
    if ($EnableLogging) {
        Write-Host "`nLog-Datei: $([Logger]::CurrentLogFile)" -ForegroundColor Cyan
    }
}
#EndRegion Main
