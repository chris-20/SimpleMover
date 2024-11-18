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
.NOTES
    Version: 2.0.0
    Author: [IHR_NAME]
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
    [int]$KeepBackupDays = 7
)
#EndRegion Parameters

#Region Classes
class FileNameCleaner {
    static [string] Clean([string]$fileName, [bool]$umlauts, [bool]$spaces, [bool]$specialChars) {
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
        
        return $result
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
            
            foreach ($file in $files) {
                $currentFile++
                $percent = [math]::Round(($currentFile / $totalFiles) * 100)
                
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
                TotalSize = ($files | Measure-Object -Property Length -Sum).Sum
            } | ConvertTo-Json
            
            Set-Content -Path $infoPath -Value $backupInfo
            
            Write-Host "  ✓ Backup erstellt: $($files.Count) Dateien" -ForegroundColor Green
            Write-Host "  📂 Speicherort: $backupPath" -ForegroundColor Yellow
            Write-Host "╚═════════════════════════════════════╝`n" -ForegroundColor Blue
            
            return $backupPath
        }
        catch {
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
            
            Write-Host "  ✓ Wiederherstellung abgeschlossen" -ForegroundColor Green
            Write-Host "  📂 Wiederhergestellte Dateien: $totalFiles" -ForegroundColor Yellow
        }
        catch {
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
        $backups = Get-ChildItem -Path ([BackupManager]::BackupRoot) -Directory
        
        foreach ($backup in $backups) {
            $infoPath = Join-Path $backup.FullName "backup_info.json"
            if (Test-Path $infoPath) {
                $info = Get-Content -Path $infoPath | ConvertFrom-Json
                Write-Host "`nBackup: $($backup.Name)" -ForegroundColor Yellow
                Write-Host "  ├─ Erstellt: $($info.CreatedAt)"
                Write-Host "  ├─ Dateien: $($info.FileCount)"
                Write-Host "  └─ Größe: $([math]::Round($info.TotalSize / 1MB, 2)) MB"
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
            Write-Host "Altes Backup entfernt: $($backup.Name)" -ForegroundColor Yellow
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
        
        $changesFound = $false
        $totalSize = 0
        $affectedFiles = 0
        
        Write-Host "📂 Zielordner: $destination`n" -ForegroundColor Yellow
        Write-Host "Geplante Änderungen:" -ForegroundColor Green
        
        foreach ($file in $files) {
            $newName = $file.Name
            if ($clean) {
                $newName = [FileNameCleaner]::Clean($newName, $umlauts, $spaces, $specialChars)
            }
            
            $totalSize += $file.Length
            if ($file.Name -ne $newName) {
                $affectedFiles++
                $changesFound = $true
                Write-Host "  ├─ Umbenennen:" -ForegroundColor Yellow
                Write-Host "  │  Von: $($file.Name)" -ForegroundColor Gray
                Write-Host "  │  Nach: $newName" -ForegroundColor White
            } else {
                Write-Host "  ├─ Unverändert: $($file.Name)" -ForegroundColor DarkGray
            }
        }
        
        Write-Host "`nZusammenfassung:" -ForegroundColor Cyan
        Write-Host "  ├─ Dateien gesamt: $($files.Count)"
        Write-Host "  ├─ Dateien betroffen: $affectedFiles"
        Write-Host "  ├─ Gesamtgröße: $([math]::Round($totalSize / 1MB, 2)) MB"
        Write-Host "  └─ Geschätzte Dauer: $([math]::Round($totalSize / 1MB / 10, 0)) Sekunden`n"
        
        if (-not $changesFound) {
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
            Write-Host "  ├─ $($ext.Name): $($ext.Count) Dateien"
        }
        
        Write-Host "`nGrößte Dateien:" -ForegroundColor Yellow
        $files | Sort-Object Length -Descending | Select-Object -First 5 | ForEach-Object {
            Write-Host "  ├─ $($_.Name) ($([math]::Round($_.Length / 1MB, 2)) MB)"
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
        [string]$pattern,
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
        
        $files = Get-ChildItem -Path $source -Filter $pattern
        
        if ($previewMode) {
            $proceed = [PreviewManager]::PreviewChanges(
                $files, $clean, $umlauts, $spaces, $specialChars, $destination
            )
            if (-not $proceed) {
                Write-Host "`n❌ Operation abgebrochen!" -ForegroundColor Yellow
                return
            }
        }
        
        $totalFiles = $files.Count
        $currentFile = 0
        
        foreach ($file in $files) {
            $currentFile++
            $progressPercentage = [math]::Round(($currentFile / $totalFiles) * 100)
            
            Write-Progress -Activity "Verarbeite Dateien" `
                         -Status "$progressPercentage% Complete" `
                         -PercentComplete $progressPercentage `
                         -CurrentOperation $file.Name
            
            [string]$newName = $file.Name
            if ($clean) {
                $newName = [FileNameCleaner]::Clean($newName, $umlauts, $spaces, $specialChars)
            }
            
            try {
                [string]$destinationFile = Join-Path $destination $newName
                Move-Item -Path $file.FullName -Destination $destinationFile -ErrorAction Stop
                Write-Host "[$progressPercentage%] ✓ " -ForegroundColor Green -NoNewline
                Write-Host "$($file.Name) -> $newName"
            }
            catch {
                Write-Host "[$progressPercentage%] ✗ " -ForegroundColor Red -NoNewline
                Write-Host "$($file.Name): $($_.Exception.Message)"
            }
        }
        
        Write-Progress -Activity "Verarbeite Dateien" -Completed
        [FileOperation]::ShowSummary($currentFile)
    }
    
    static [bool] ValidatePaths([string]$source, [string]$destination) {
        if (-not (Test-Path $source)) {
            Write-Host "❌ Quellordner nicht gefunden: $source" -ForegroundColor Red
            return $false
        }
        
        if (-not (Test-Path $destination)) {
            Write-Host "📁 Erstelle Zielordner: $destination" -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $destination | Out-Null
        }
        
        return $true
    }
    
    static [void] ShowSummary([int]$processedFiles) {
        Write-Host "`n═══════════════ Zusammenfassung ═══════════════" -ForegroundColor Cyan
        Write-Host "📊 Verarbeitete Dateien: $processedFiles"
        Write-Host "⏱️ Beendet: $(Get-Date -Format 'HH:mm:ss')"
        Write-Host "═════════════════════════════════════════════`n" -ForegroundColor Cyan
    }
}
#EndRegion Classes

#Region Main
try {
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
        } else {
            Write-Host "Keine Backups gefunden!" -ForegroundColor Red
        }
        exit 0
    }

    # Interaktiver Modus
    if (-not $SourcePath -or -not $DestinationPath) {
        Write-Host "`n📂 Pfade Konfiguration" -ForegroundColor Yellow
        $SourcePath = Read-Host "Quellpfad eingeben"
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
        $FilePattern,
        $CleanFileNames,
        $ReplaceUmlauts,
        $RemoveSpaces,
        $RemoveSpecialChars,
        $Preview
    )
}
catch {
    Write-Host "`n❌ Unerwarteter Fehler:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
#EndRegion Main
