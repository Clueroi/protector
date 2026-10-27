function Update-WindowsOS {
    [CmdletBinding()]
    param()

    Write-Host "Iniciando atualização do Windows (Windows Update)..." -ForegroundColor Cyan
    Write-Log 'Iniciando atualização do Windows (Windows Update)...' 'INFO'

    # Executa o PSWindowsUpdate num Windows PowerShell 5.1 separado (powershell.exe existe em todo Windows 10/11).
    # Script enviado via -EncodedCommand: sem problema de aspas/quebras de linha na linha de comando.
    $wuScript = @'
$ErrorActionPreference = 'Stop'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        # Máquina limpa: o 5.1 precisa do provedor NuGet antes de baixar módulos da PSGallery
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        }
        Install-Module PSWindowsUpdate -Force -Confirm:$false -Scope AllUsers -AllowClobber | Out-Null
    }

    Import-Module PSWindowsUpdate | Out-Null

    Get-WindowsUpdate `
        -Install `
        -AcceptAll `
        -IgnoreReboot `
        -MicrosoftUpdate `
        -ErrorAction Stop `
    | Out-Null

    exit 0
}
catch {
    exit 1
}
'@

    try {

        $ps51    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wuScript))

        $proc = Start-Process $ps51 `
            -ArgumentList @(
                '-NoProfile',
                '-NonInteractive',
                '-ExecutionPolicy', 'Bypass',
                '-EncodedCommand', $encoded
            ) `
            -WindowStyle Hidden `
            -Wait `
            -PassThru

        if ($proc.ExitCode -ne 0) {
            Write-Host ("Windows Update retornou erro. ExitCode={0}" -f $proc.ExitCode) -ForegroundColor Red
            Write-Log ("Windows Update retornou erro. ExitCode={0}" -f $proc.ExitCode) 'ERROR'

            throw "Windows Update retornou erro. ExitCode=$($proc.ExitCode)"
        }

        Write-Host "Atualização do Windows concluída." -ForegroundColor Green
        Write-Log 'Atualização do Windows concluída.' 'INFO'

        return [PSCustomObject]@{
            MensagemTecnica = "Atualização do Windows concluída. ExitCode=$($proc.ExitCode)"
            ExitCode        = $proc.ExitCode
        }
    }
    catch {

        Write-Host "ERRO durante Update-WindowsOS: $_" -ForegroundColor Red
        Write-Log ("Falha durante Update-WindowsOS: {0}" -f $_) 'ERROR'

        throw
    }
}