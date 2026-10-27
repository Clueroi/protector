function Update-ProtectorFiles {

    $ErrorActionPreference = "Stop"
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    $ProgressPreference   = "SilentlyContinue"

    # -------------------------------
    # Função para cabeçalho estilizado
    # -------------------------------
    function Show-Header {
        param(
            [string]$Text,
            [ConsoleColor]$Color = 'Cyan'
        )

        $bar = '─' * ($Text.Length + 2)
        Write-Host ""
        Write-Host ("┌$bar┐") -ForegroundColor $Color
        Write-Host ("│ $Text │") -ForegroundColor $Color
        Write-Host ("└$bar┘") -ForegroundColor $Color
        Write-Host ""
    }

    # -------------------------------
    # Função de falha controlada
    # -------------------------------
    function Fail {
        param ([string]$Message)
        Show-Header $Message -Color Red
        Write-Host "O script será encerrado em 5 segundos..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        exit 1
    }

    # Configurações
    $BaseUrl   = "https://github.com/Clueroi/system-defenser.git"
    $BasePath  = "C:\Protector"

    # Cache busting permanente (ANTI GitHub RAW cache)
    $NoCache   = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

    # Estrutura base (nunca apaga nada)
    $Folders = @(
        $BasePath,
        "$BasePath\Functions",
        "$BasePath\Assets\Images"
    )

    foreach ($Folder in $Folders) {
        if (-not (Test-Path $Folder)) {
            New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        }
    }

    # -------------------------------
    # Lista de arquivos oficiais
    # -------------------------------
    $Files = @(
        @{ Url = "$BaseUrl/RodaProtector.ps1";                        Path = "$BasePath\RodaProtector.new" },
        @{ Url = "$BaseUrl/ElevaProtector.ps1";                       Path = "$BasePath\ElevaProtector.new" },
        @{ Url = "$BaseUrl/Functions/Update-ProtectorFiles.ps1";      Path = "$BasePath\Functions\Update-ProtectorFiles.new" },

        @{ Url = "$BaseUrl/Atualiza.ps1";                            Path = "$BasePath\Atualiza.ps1" },
        @{ Url = "$BaseUrl/CriaCredenciais.ps1";                     Path = "$BasePath\CriaCredenciais.ps1" },
        @{ Url = "$BaseUrl/Protector.ps1";                            Path = "$BasePath\Protector.ps1" },
        @{ Url = "$BaseUrl/Prepara.ps1";                             Path = "$BasePath\Prepara.ps1" },
        @{ Url = "$BaseUrl/Assets/Images/eric-bg.png";              Path = "$BasePath\Assets\Images\eric-bg.png" },
        @{ Url = "$BaseUrl/Assets/Images/eric-bg.png";           Path = "$BasePath\Assets\Images\eric-bg.png" },
        @{ Url = "$BaseUrl/Assets/Images/eric-bg.png";       Path = "$BasePath\Assets\Images\eric-bg.png" },
        @{ Url = "$BaseUrl/Functions/Block-AppUpdates.ps1";          Path = "$BasePath\Functions\Block-AppUpdates.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-AllRecycleBins.ps1";      Path = "$BasePath\Functions\Clear-AllRecycleBins.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-BrowserCache.ps1";        Path = "$BasePath\Functions\Clear-BrowserCache.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-RecentFilesHistory.ps1";  Path = "$BasePath\Functions\Clear-RecentFilesHistory.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-TempFiles.ps1";           Path = "$BasePath\Functions\Clear-TempFiles.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-WindowsUpdateCache.ps1";  Path = "$BasePath\Functions\Clear-WindowsUpdateCache.ps1" },
        @{ Url = "$BaseUrl/Functions/Confirm-MacriumBackup.ps1";     Path = "$BasePath\Functions\Confirm-MacriumBackup.ps1" },
        @{ Url = "$BaseUrl/Functions/Get-SystemInventory.ps1";       Path = "$BasePath\Functions\Get-SystemInventory.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-HDD.ps1";              Path = "$BasePath\Functions\Optimize-HDD.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-JsonReport.ps1";       Path = "$BasePath\Functions\Optimize-JsonReport.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-NetworkSettings.ps1";  Path = "$BasePath\Functions\Optimize-NetworkSettings.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-PowerSettings.ps1";    Path = "$BasePath\Functions\Optimize-PowerSettings.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-SSD.ps1";              Path = "$BasePath\Functions\Optimize-SSD.ps1" },
        @{ Url = "$BaseUrl/Functions/Remove-OldUpdateFiles.ps1";     Path = "$BasePath\Functions\Remove-OldUpdateFiles.ps1" },
        @{ Url = "$BaseUrl/Functions/Repair-SystemIntegrity.ps1";    Path = "$BasePath\Functions\Repair-SystemIntegrity.ps1" },
        @{ Url = "$BaseUrl/Functions/Scan-AntiMalware.ps1";          Path = "$BasePath\Functions\Scan-AntiMalware.ps1" },
        @{ Url = "$BaseUrl/Functions/Send-LogToServer.ps1";          Path = "$BasePath\Functions\Send-LogToServer.ps1" },
        @{ Url = "$BaseUrl/Functions/Show-ProtectorEndUI.ps1";        Path = "$BasePath\Functions\Show-ProtectorEndUI.ps1" },
        @{ Url = "$BaseUrl/Functions/Show-ProtectorUI.ps1";           Path = "$BasePath\Functions\Show-ProtectorUI.ps1" },
        @{ Url = "$BaseUrl/Functions/Update-MicrosoftStore.ps1";     Path = "$BasePath\Functions\Update-MicrosoftStore.ps1" },
        @{ Url = "$BaseUrl/Functions/Update-WindowsOS.ps1";          Path = "$BasePath\Functions\Update-WindowsOS.ps1" },
        @{ Url = "$BaseUrl/Functions/Update-WingetApps.ps1";         Path = "$BasePath\Functions\Update-WingetApps.ps1" },
        @{ Url = "$BaseUrl/Functions/Write-JsonResult.ps1";          Path = "$BasePath\Functions\Write-JsonResult.ps1" }
    )

    Show-Header "Baixando arquivos do Protector..." -Color Yellow

    foreach ($File in $Files) {
        try {
            if (Test-Path $File.Path) {
                attrib -R $File.Path 2>$null
            }
        }
        catch {
            Write-Host "Aviso: Não foi possível mudar os atributos dos arquivos $($File.Path)" -ForegroundColor DarkYellow
        }
    }

    Show-Header "Atualizando Protector..." -Color Cyan

    foreach ($File in $Files) {
        try {
            Invoke-WebRequest `
                -Uri "$($File.Url)$NoCache" `
                -OutFile $File.Path `
                -UseBasicParsing `
                -Headers @{ "Cache-Control"="no-cache" } `
                -ErrorAction Stop
        }
        catch {

            if ($File.Path -match "\.png$") {
                Write-Host "Aviso: Falha ao baixar imagem $($File.Path)" -ForegroundColor DarkYellow
                continue
            }

            Fail "Falha crítica ao atualizar: $($File.Path)"
        }
    }

# Atualização dos arquivos que estavam na memória
$AtomicTargets = @(
    @{ New = "$BasePath\RodaProtector.new";                    Final = "$BasePath\RodaProtector.ps1" },
    @{ New = "$BasePath\ElevaProtector.new";                   Final = "$BasePath\ElevaProtector.ps1" },
    @{ New = "$BasePath\Functions\Update-ProtectorFiles.new";  Final = "$BasePath\Functions\Update-ProtectorFiles.ps1" }
)

foreach ($item in $AtomicTargets) {

    $src = $item.New
    $dst = $item.Final

    if (-not (Test-Path $src)) {
        continue
    }

    try {

        if (Test-Path $dst) {
            try {
                Set-ItemProperty -Path $dst -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            }
            catch {}
        }

        Move-Item -Path $src -Destination $dst -Force -ErrorAction Stop
    }
    catch {
        Write-Host "Aviso: não foi possível atualizar $dst" -ForegroundColor DarkYellow
    }
}

    Show-Header "Atualização concluída com sucesso!" -Color Green
}

Update-ProtectorFiles