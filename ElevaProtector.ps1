# ElevaProtector.ps1
# Executa Protector.ps1 em PowerShell 7 usando credenciais criptografadas (AES)
# Responsável por elevação, contexto de execução e repasse seguro de parâmetros

[CmdletBinding()]
param (
    # Infraestrutura
    [string]$PwshPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'),   # Windows PowerShell 5.1 (já vem no Windows)
    [string]$ScriptPath = 'C:\Protector\Protector.ps1',
    [string]$CredPath   = 'C:\Protector\credenciais.xml',
    [string]$KeyPath    = 'C:\Protector\chave.key',

    # Opções de janela
    [switch]$NoWindow,
    [switch]$NonInteractive,
    [switch]$Maximized,

    # Parâmetros para Protector.ps1
    [int[]]$ExecutaFases,
    [int[]]$PulaFases,
    [ValidateSet('INFO','WARN','ERROR','DEBUG')] [string]$LogLevel,
    [switch]$Simulado,
    [string]$FileServer,
    [string]$Cliente
)

# -------------------------------
# Funções auxiliares
# -------------------------------
function Show-Header {
    param([string]$Text,[ConsoleColor]$Color='Cyan')
    $bar = '─' * ($Text.Length + 2)
    Write-Host ""
    Write-Host ("┌$bar┐") -ForegroundColor $Color
    Write-Host ("│ $Text │") -ForegroundColor $Color
    Write-Host ("└$bar┘") -ForegroundColor $Color
    Write-Host ""
}

function Fail {
    param([string]$Message)
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

$BaseUrl  = "https://raw.githubusercontent.com/Clueroi/protector/blob/main/Functions/Update-ProtectorFiles.ps1"
$DestPath = "C:\Protector\Functions\Update-ProtectorFiles.ps1"
$NoCache  = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

# Remove o arquivo antigo
# Remove-Item -Path $DestPath -Force -ErrorAction SilentlyContinue

# Baixa o novo arquivo
Invoke-WebRequest -Uri ($BaseUrl + $NoCache) `
                  -OutFile $DestPath `
                  -UseBasicParsing `
                  -ErrorAction SilentlyContinue


# Atualização dos arquivos do Protector usando a função Update-ProtectorFiles.ps1, que foi atualizada no cod acima
$updater = "C:\Protector\Functions\Update-ProtectorFiles.ps1"
if (Test-Path $updater) {
    . $updater
    Update-ProtectorFiles
}

#endregion


# -------------------------------
# Validações iniciais (versão amigável)
# -------------------------------

if (-not (Test-Path -LiteralPath $PwshPath)) {
    Fail "powershell.exe não foi localizado em: $PwshPath"
}

if (-not (Test-Path $ScriptPath)) {
    Fail "Arquivo principal do Protector não foi encontrado. Caminho esperado:$ScriptPath"
}
$ScriptPath = (Resolve-Path $ScriptPath).Path

if (-not (Test-Path $CredPath)) {
    Fail "Arquivo de credenciais não encontrado. Local esperado:$CredPath"
}
$CredPath = (Resolve-Path $CredPath).Path

if (-not (Test-Path $KeyPath)) {
    Fail "Chave AES ausente.`n`nSem a chave não é possível descriptografar as credenciais. Local esperado:$KeyPath"
}
$KeyPath = (Resolve-Path $KeyPath).Path


# -------------------------------
# Leitura das credenciais AES
# -------------------------------
try {
    [xml]$xml = Get-Content -LiteralPath $CredPath -Raw
    $user = $xml.Credenciais.UserName
    $enc  = $xml.Credenciais.EncryptedPassword
} catch { Fail "Falha ao ler credenciais: $($_.Exception.Message)" }

if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($enc)) {
    Fail "Credenciais incompletas (UserName / EncryptedPassword)."
}

try {
    $keyBytes = [IO.File]::ReadAllBytes($KeyPath)
    $secure   = ConvertTo-SecureString -String $enc -Key $keyBytes
    if ($user -notlike '*\*' -and $user -notlike '*@*') { $user = "$env:COMPUTERNAME\$user" }
    $cred     = [System.Management.Automation.PSCredential]::new($user,$secure)
} catch { Fail "Não foi possível abrir as credenciais. Verifique chave AES." }

# =========================================================
# >>> PATCH JSON IPC (ARGUMENTOS ROBUSTOS)
# =========================================================

$argJsonPath = "C:\Protector\protector_arg.json"

$argsObj = @{
    FileServer    = $FileServer
    Cliente       = $Cliente
    ExecutaFases  = $ExecutaFases
    PulaFases     = $PulaFases
    LogLevel      = $LogLevel
    Simulado      = [bool]$Simulado
}

try {
    $argsObj | ConvertTo-Json -Depth 5 | Set-Content -Path $argJsonPath -Encoding UTF8
}
catch {
    Fail "Falha ao criar protector_arg.json: $($_.Exception.Message)"
}

# =========================================================

# -------------------------------
# Montagem segura do comando
# -------------------------------
# NÃO repassar mais argumentos pela linha de comando
$argString = "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`""
if ($NonInteractive) { $argString += " -NonInteractive" }

# -------------------------------
# Configuração da janela
# -------------------------------
$winStyle = if ($NoWindow) { 'Hidden' } elseif ($Maximized) { 'Maximized' } else { 'Normal' }

# -------------------------------
# Log do comando final
# -------------------------------
Show-Header "Comando final:" -Color Yellow
Write-Host "$PwshPath $argString" -ForegroundColor Cyan

# -------------------------------
# Execução do Protector
# -------------------------------
try {
    $proc = Start-Process `
        -FilePath $PwshPath `
        -ArgumentList $argString `
        -Credential $cred `
        -WorkingDirectory (Split-Path $ScriptPath -Parent) `
        -WindowStyle $winStyle `
        -UseNewEnvironment `
        -PassThru

    Show-Header "Protector iniciado com sucesso. PID: $($proc.Id)" -Color Green
}
catch {
    Fail "Falha ao iniciar Protector.ps1: $($_.Exception.Message)"
}