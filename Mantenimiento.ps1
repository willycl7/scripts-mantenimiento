#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Write-Header {
    param([string]$Texto)
    Write-Host ""
    Write-Host ("=" * 65) -ForegroundColor Cyan
    Write-Host "  $Texto" -ForegroundColor White
    Write-Host ("=" * 65) -ForegroundColor Cyan
}

function Write-Step { param([string]$t); Write-Host "  >> $t" -ForegroundColor Yellow }
function Write-OK   { param([string]$t); Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-WARN { param([string]$t); Write-Host "  [!]  $t" -ForegroundColor DarkYellow }
function Write-ERR  { param([string]$t); Write-Host "  [X]  $t" -ForegroundColor Red }
function Write-INFO { param([string]$t); Write-Host "  [i]  $t" -ForegroundColor Gray }

$LogDir  = "$env:USERPROFILE\Desktop\Mantenimiento_Logs"
$LogFile = "$LogDir\mantenimiento_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

function Write-Log {
    param([string]$Msg)
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
}

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "       MANTENIMIENTO LOGICO DEL EQUIPO - PowerShell v2.0      " -ForegroundColor White
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1]  Limpieza de archivos temporales" -ForegroundColor White
    Write-Host "  [2]  Limpiar cache DNS" -ForegroundColor White
    Write-Host "  [3]  Reparar archivos del sistema (SFC + DISM)" -ForegroundColor White
    Write-Host "  [4]  Desfragmentar / Optimizar discos" -ForegroundColor White
    Write-Host "  [5]  Actualizar Windows Update" -ForegroundColor White
    Write-Host "  [6]  Actualizar aplicaciones (winget)" -ForegroundColor White
    Write-Host "  [7]  Limpiar prefetch y cache de Windows" -ForegroundColor White
    Write-Host "  [8]  Gestion de programas de inicio" -ForegroundColor White
    Write-Host "  [9]  Verificar salud del disco (ChkDsk)" -ForegroundColor White
    Write-Host "  [10] Liberar RAM" -ForegroundColor White
    Write-Host "  [11] Limpiar logs de eventos" -ForegroundColor White
    Write-Host "  [12] ** MANTENIMIENTO COMPLETO (todas las tareas) **" -ForegroundColor Yellow
    Write-Host "  [0]  Salir" -ForegroundColor White
    Write-Host ""
    Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-LimpiezaTemporales {
    Write-Header "1. LIMPIEZA DE ARCHIVOS TEMPORALES"
    Write-Log "INICIO: Limpieza temporales"

    $rutas = @(
        $env:TEMP,
        "$env:SystemRoot\Temp",
        "$env:LOCALAPPDATA\Temp",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
    )

    $totalMB = 0
    foreach ($ruta in $rutas) {
        if (Test-Path $ruta) {
            Write-Step "Limpiando: $ruta"
            try {
                $antes = (Get-ChildItem $ruta -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                Get-ChildItem -Path $ruta -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                $despues = (Get-ChildItem $ruta -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $mb = [math]::Round((($antes - $despues) / 1MB), 2)
                $totalMB += $mb
                Write-OK "Liberado: $mb MB"
            } catch {
                Write-WARN "No se pudo limpiar completamente: $ruta"
            }
        }
    }

    Write-Step "Ejecutando Liberador de espacio de disco (cleanmgr)..."
    try {
        $sageset = 65535
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        Get-ChildItem $regPath | ForEach-Object {
            try { Set-ItemProperty -Path $_.PSPath -Name "StateFlags$sageset" -Value 2 -Type DWORD -ErrorAction SilentlyContinue } catch {}
        }
        Start-Process "cleanmgr.exe" -ArgumentList "/sagerun:$sageset" -Wait -NoNewWindow
        Write-OK "Liberador de espacio completado"
    } catch {
        Write-WARN "cleanmgr no disponible"
    }

    Write-OK "Total estimado liberado: $totalMB MB"
    Write-Log "FIN: Limpieza temporales - $totalMB MB"
}

function Invoke-LimpiarDNS {
    Write-Header "2. LIMPIAR CACHE DNS"
    Write-Log "INICIO: DNS"
    try {
        ipconfig /flushdns | Out-Null
        Clear-DnsClientCache -ErrorAction Stop
        Write-OK "Cache DNS limpiada"
        Write-Log "DNS OK"
    } catch {
        Write-ERR "Error al limpiar DNS: $_"
    }
    try { nbtstat -RR | Out-Null; Write-OK "Cache NetBIOS actualizada" } catch {}
    Write-INFO "Para reset de red profundo ejecuta: netsh winsock reset"
}

function Invoke-RepararSistema {
    Write-Header "3. REPARACION DE ARCHIVOS DEL SISTEMA"
    Write-Log "INICIO: SFC + DISM"
    Write-WARN "Este proceso puede tardar 10-30 minutos..."

    Write-Step "DISM - Verificando imagen de Windows..."
    try {
        $p = Start-Process "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -eq 0) { Write-OK "DISM completado sin errores" }
        else { Write-WARN "DISM codigo: $($p.ExitCode)" }
        Write-Log "DISM exitCode=$($p.ExitCode)"
    } catch { Write-ERR "Error DISM: $_" }

    Write-Step "SFC - Verificando integridad de archivos..."
    try {
        $p = Start-Process "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -eq 0) { Write-OK "SFC: Sin violaciones de integridad" }
        else { Write-WARN "SFC codigo: $($p.ExitCode)" }
        Write-Log "SFC exitCode=$($p.ExitCode)"
    } catch { Write-ERR "Error SFC: $_" }

    Write-Log "FIN: SFC + DISM"
}

function Invoke-OptimizarDiscos {
    Write-Header "4. OPTIMIZAR / DESFRAGMENTAR DISCOS"
    Write-Log "INICIO: Optimizacion discos"

    $volumenes = Get-Volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq 'Fixed' }
    foreach ($vol in $volumenes) {
        $letra   = $vol.DriveLetter
        $totalGB = [math]::Round($vol.Size / 1GB, 1)
        $libreGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
        Write-Step "Disco ${letra}: - Total: $totalGB GB - Libre: $libreGB GB"

        try {
            $mediaType = "Unspecified"
            try {
                $disk = Get-Partition -DriveLetter $letra -ErrorAction SilentlyContinue | Get-Disk -ErrorAction SilentlyContinue
                if ($disk) {
                    $mediaType = (Get-PhysicalDisk | Where-Object { $_.DeviceID -eq $disk.Number }).MediaType
                }
            } catch {}

            if ($mediaType -eq "SSD") {
                Write-INFO "SSD detectado - Ejecutando TRIM..."
                Optimize-Volume -DriveLetter $letra -ReTrim -Verbose
                Write-OK "TRIM completado en ${letra}:"
                Write-Log "TRIM SSD ${letra}: OK"
            } else {
                Write-INFO "HDD detectado - Desfragmentando..."
                Optimize-Volume -DriveLetter $letra -Defrag -Verbose
                Write-OK "Desfragmentacion completada en ${letra}:"
                Write-Log "Defrag HDD ${letra}: OK"
            }
        } catch {
            Write-WARN "No se pudo optimizar ${letra}: $_"
        }
    }
    Write-Log "FIN: Optimizacion discos"
}

function Invoke-ActualizarWindows {
    Write-Header "5. ACTUALIZAR WINDOWS"
    Write-Log "INICIO: Windows Update"

    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Step "Instalando modulo PSWindowsUpdate..."
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
            Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber
            Write-OK "Modulo instalado"
        } catch {
            Write-WARN "No se pudo instalar PSWindowsUpdate. Abriendo Windows Update..."
            Start-Process "ms-settings:windowsupdate"
            return
        }
    }

    try {
        Import-Module PSWindowsUpdate -Force
        Write-Step "Buscando actualizaciones..."
        $updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
        if ($updates.Count -eq 0) {
            Write-OK "El sistema esta actualizado."
        } else {
            Write-INFO "Se encontraron $($updates.Count) actualizacion(es). Instalando..."
            Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Confirm:$false
            Write-OK "Actualizaciones instaladas. Puede requerirse reinicio."
        }
        Write-Log "Windows Update: $($updates.Count) actualizaciones"
    } catch {
        Write-ERR "Error en Windows Update: $_"
        Start-Process "ms-settings:windowsupdate"
    }
}

function Invoke-ActualizarApps {
    Write-Header "6. ACTUALIZAR APLICACIONES (winget)"
    Write-Log "INICIO: winget"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-WARN "winget no disponible. Instala 'App Installer' desde Microsoft Store."
        return
    }

    Write-Step "Actualizando todas las aplicaciones..."
    winget upgrade --all --accept-package-agreements --accept-source-agreements
    Write-OK "Actualizacion de apps completada"
    Write-Log "winget upgrade completado"
}

function Invoke-LimpiarCache {
    Write-Header "7. LIMPIAR PREFETCH Y CACHE DE WINDOWS"
    Write-Log "INICIO: Cache"

    Write-Step "Limpiando Prefetch..."
    try {
        Remove-Item "$env:SystemRoot\Prefetch\*" -Force -ErrorAction SilentlyContinue
        Write-OK "Prefetch limpiado"
    } catch { Write-WARN "Prefetch: $_" }

    Write-Step "Limpiando cache de fuentes..."
    try {
        Stop-Service -Name "FontCache" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache*" -Force -ErrorAction SilentlyContinue
        Start-Service -Name "FontCache" -ErrorAction SilentlyContinue
        Write-OK "Cache de fuentes limpiada"
    } catch { Write-WARN "FontCache: $_" }

    Write-Step "Limpiando cache de Windows Update..."
    try {
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Write-OK "Cache de Windows Update limpiada"
    } catch { Write-WARN "WU Cache: $_" }

    Write-Step "Limpiando cache de miniaturas..."
    try {
        Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
        Write-OK "Cache de miniaturas limpiada"
    } catch { Write-WARN "Thumbcache: $_" }

    Write-Log "FIN: Cache limpiada"
}

function Invoke-GestionInicio {
    Write-Header "8. PROGRAMAS DE INICIO"
    Write-Log "INICIO: Gestion inicio"

    $regs = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    )

    Write-Host ""
    Write-Host "  Programas que inician con Windows:" -ForegroundColor White
    Write-Host ""

    foreach ($reg in $regs) {
        if (Test-Path $reg) {
            $scope = if ($reg -like "HKLM*") { "Sistema" } else { "Usuario" }
            Write-Host "  [$scope]" -ForegroundColor Cyan
            $items = Get-ItemProperty -Path $reg
            $items.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                Write-Host "    - $($_.Name)" -ForegroundColor White
                Write-Host "      $($_.Value)" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
    Write-INFO "Para desactivar: Administrador de tareas > pestana Inicio"
    Write-Log "Gestion inicio completada"

    $resp = Read-Host "  Abrir Administrador de Tareas? (s/n)"
    if ($resp -eq 's') { Start-Process taskmgr }
}

function Invoke-CheckDisk {
    Write-Header "9. VERIFICAR SALUD DEL DISCO (CHKDSK)"
    Write-Log "INICIO: ChkDsk"

    $volumenes = Get-Volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq 'Fixed' }
    foreach ($vol in $volumenes) {
        $letra = $vol.DriveLetter
        Write-Step "Analizando disco ${letra}:"
        try {
            $resultado = Repair-Volume -DriveLetter $letra -Scan
            switch ($resultado) {
                "NoErrorsFound"       { Write-OK "Sin errores en ${letra}:" }
                "ErrorsFound"         { Write-WARN "Errores encontrados en ${letra}: Ejecutar con -OfflineScanAndFix" }
                "OfflineScanRequired" { Write-WARN "Se requiere analisis offline para ${letra}:" }
                default               { Write-INFO "Resultado ${letra}: $resultado" }
            }
            Write-Log "ChkDsk ${letra}: $resultado"
        } catch {
            Write-ERR "Error en ChkDsk ${letra}: $_"
        }
    }
    Write-INFO "Para verificacion profunda: chkdsk C: /f /r  (requiere reinicio)"
}

function Invoke-LiberarRAM {
    Write-Header "10. LIBERAR MEMORIA RAM"
    Write-Log "INICIO: RAM"

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $antesGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    Write-Step "RAM libre antes: $antesGB GB / $totalGB GB total"

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    Write-OK "GC .NET completada"

    $liberados = 0
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.MinWorkingSet = $_.MinWorkingSet; $liberados++ } catch {}
    }
    Write-OK "$liberados procesos optimizados"

    $os2 = Get-CimInstance -ClassName Win32_OperatingSystem
    $despuesGB = [math]::Round($os2.FreePhysicalMemory / 1MB, 2)
    $ganancia  = [math]::Round($despuesGB - $antesGB, 2)
    Write-OK "RAM libre despues: $despuesGB GB  (Ganancia: +$ganancia GB)"
    Write-Log "RAM: antes=$antesGB GB | despues=$despuesGB GB"
}

function Invoke-LimpiarLogs {
    Write-Header "11. LIMPIAR LOGS DE EVENTOS DE WINDOWS"
    Write-Log "INICIO: Event Logs"

    Write-Step "Logs con mas eventos:"
    $logList = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
        Where-Object { $_.RecordCount -gt 0 } |
        Sort-Object RecordCount -Descending |
        Select-Object -First 15

    foreach ($log in $logList) {
        $fileSizeMB = [math]::Round($log.FileSize / 1MB, 1)
        Write-Host "    $($log.LogName): $($log.RecordCount) eventos ($fileSizeMB MB)" -ForegroundColor DarkGray
    }

    Write-Host ""
    $resp = Read-Host "  Limpiar logs de Sistema, Aplicacion y Seguridad? (s/n)"
    if ($resp -ne 's') { return }

    foreach ($logName in @("System", "Application", "Security", "Setup")) {
        try {
            wevtutil cl $logName 2>$null
            Write-OK "Log '$logName' limpiado"
            Write-Log "EventLog $logName limpiado"
        } catch {
            Write-WARN "No se pudo limpiar '$logName'"
        }
    }
}

function Show-Reporte {
    Write-Header "RESUMEN DEL SISTEMA"
    $os  = Get-CimInstance -ClassName Win32_OperatingSystem
    $cpu = (Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1).Name.Trim()
    $ramTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $ramLibreGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $uptime = (New-TimeSpan -Start $os.LastBootUpTime)

    Write-Host ""
    Write-Host "  Sistema   : $($os.Caption) Build $($os.BuildNumber)" -ForegroundColor White
    Write-Host "  CPU       : $cpu" -ForegroundColor White
    Write-Host "  RAM       : $ramLibreGB GB libre / $ramTotalGB GB total" -ForegroundColor White
    Write-Host "  Encendido : $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m" -ForegroundColor White
    Write-Host ""

    Get-Volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
        $totalGB = [math]::Round($_.Size / 1GB, 1)
        $libreGB = [math]::Round($_.SizeRemaining / 1GB, 1)
        $pct = if ($totalGB -gt 0) { [math]::Round(($libreGB / $totalGB) * 100, 0) } else { 0 }
        $color = if ($pct -gt 20) { "Green" } elseif ($pct -gt 10) { "Yellow" } else { "Red" }
        $letra = $_.DriveLetter
        Write-Host "  Disco ${letra}: $libreGB GB libre / $totalGB GB total ($pct% libre)" -ForegroundColor $color
    }

    Write-Host ""
    Write-OK "Log guardado en: $LogFile"
    Write-Host ""
    Write-Log "=== FIN DE MANTENIMIENTO ==="
}

# ══════════════════════════════════════════════════════════════════════════════
Write-Log "=== INICIO DE MANTENIMIENTO ==="
Write-Log "Usuario: $env:USERNAME | Equipo: $env:COMPUTERNAME"

do {
    Show-Menu
    $opcion = Read-Host "  Selecciona una opcion"

    switch ($opcion) {
        "1"  { Invoke-LimpiezaTemporales }
        "2"  { Invoke-LimpiarDNS }
        "3"  { Invoke-RepararSistema }
        "4"  { Invoke-OptimizarDiscos }
        "5"  { Invoke-ActualizarWindows }
        "6"  { Invoke-ActualizarApps }
        "7"  { Invoke-LimpiarCache }
        "8"  { Invoke-GestionInicio }
        "9"  { Invoke-CheckDisk }
        "10" { Invoke-LiberarRAM }
        "11" { Invoke-LimpiarLogs }
        "12" {
            Write-Header "** MANTENIMIENTO COMPLETO **"
            Write-WARN "Este proceso puede tardar entre 30 y 90 minutos."
            $conf = Read-Host "  Confirmas? (s/n)"
            if ($conf -eq 's') {
                Invoke-LimpiezaTemporales
                Invoke-LimpiarDNS
                Invoke-LimpiarCache
                Invoke-CheckDisk
                Invoke-RepararSistema
                Invoke-OptimizarDiscos
                Invoke-ActualizarWindows
                Invoke-ActualizarApps
                Invoke-LiberarRAM
                Invoke-LimpiarLogs
            }
        }
        "0" {
            Show-Reporte
            Write-Host "  Mantenimiento finalizado. Reinicia el equipo si fue solicitado." -ForegroundColor Cyan
            Write-Host ""
            break
        }
        default { Write-WARN "Opcion no valida. Intenta de nuevo." }
    }

    if ($opcion -ne "0" -and $opcion -ne "8") {
        Show-Reporte
        Read-Host "  Presiona ENTER para volver al menu"
    }

} while ($opcion -ne "0")
