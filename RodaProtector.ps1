# RodaProtector.ps1
[CmdletBinding()]
param (
    # Caminho do PowerShell 7
    [string]$PwshPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'),   # Windows PowerShell 5.1 (já vem no Windows)
    # Caminho do script principal Protector
    [string]$ScriptPath = 'C:\Protector\Protector.ps1',

    # Opções de janela
    [switch]$NoWindow,
    [switch]$NonInteractive,
    [switch]$Maximized,

    # Parâmetros para Protector.ps1
    [int[]]$ExecutaFases,
    [int[]]$PulaFases,

    [ValidateSet('INFO','WARN','ERROR','DEBUG')]
    [string]$LogLevel,
    [switch]$Simulado,
    [string]$FileServer,
    [string]$Cliente
)

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



# -------------------------------------------------------------------------------------------------------------------------
#region BootStrap - Atualiza somente o arquivo Update-ProtectorFiles.ps1 — versão mínima e silenciosa
# -------------------------------------------------------------------------------------------------------------------------

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
New-Item -ItemType Directory -Path 'C:\Protector\Functions' -Force -ErrorAction SilentlyContinue | Out-Null   # 1ª execução em máquina limpa

$BaseUrl  = "https://raw.githubusercontent.com/IT4You-Scripts/Protector360/main/Functions/Update-ProtectorFiles.ps1"
$DestPath = "C:\Protector\Functions\Update-ProtectorFiles.ps1"
$NoCache  = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

# Remove o arquivo antigo
# Remove-Item -Path $DestPath -Force -ErrorAction SilentlyContinue

# Baixa o novo arquivo
Invoke-WebRequest -Uri ($BaseUrl + $NoCache) `
                  -OutFile $DestPath `
                  -UseBasicParsing `
                  -ErrorAction SilentlyContinue


# Atualização dos arquivos do Protector 360 usando a função Update-ProtectorFiles.ps1, que foi atualizada no cod acima
$updater = "C:\Protector\Functions\Update-ProtectorFiles.ps1"
if (Test-Path $updater) {
    . $updater
    Update-ProtectorFiles
}

#endregion


# -------------------------------
# Validações
# -------------------------------
if (-not (Test-Path -LiteralPath $PwshPath))   { Fail "powershell.exe não encontrado em: $PwshPath" }
if (-not (Test-Path -LiteralPath $ScriptPath)) { Fail "Protector.ps1 não encontrado em: $ScriptPath" }

# Desbloqueia o script alvo
try { Unblock-File -Path $ScriptPath -ErrorAction SilentlyContinue } catch {}

# Diretório de trabalho
$workDir = Split-Path -Path $ScriptPath -Parent

# -------------------------------
# Montagem segura dos argumentos
# -------------------------------
$argList = @('-ExecutionPolicy','Bypass','-NoProfile','-File',$ScriptPath)
if ($NonInteractive) { $argList += '-NonInteractive' }
if ($ExecutaFases)   { $argList += '-ExecutaFases'; $argList += ($ExecutaFases -join ',') }
if ($PulaFases)      { $argList += '-PulaFases'; $argList += ($PulaFases -join ',') }
if ($LogLevel)       { $argList += '-LogLevel'; $argList += $LogLevel }
if ($Simulado)       { $argList += '-Simulado' }
if ($FileServer)     { $argList += '-FileServer'; $argList += $FileServer }
if ($Cliente)        { $argList += '-Cliente'; $argList += "`"$Cliente`"" }

# -------------------------------
# Configuração da janela
# -------------------------------
$winStyle = if ($NoWindow) { 'Hidden' } elseif ($Maximized) { 'Maximized' } else { 'Normal' }

# -------------------------------
# Log do comando final para debug
# -------------------------------
Show-Header "Comando final:" -Color Yellow
Write-Host "$PwshPath $($argList -join ' ')" -ForegroundColor Cyan

# -------------------------------
# Execução do Protector
# -------------------------------
Push-Location $workDir
try {
    & $PwshPath @argList
    Show-Header "Protector executado com sucesso!" -Color Green
} catch {
    Fail "Falha ao iniciar o Protector.ps1: $($_.Exception.Message)"
}
Pop-Location