\xEF\xBB\xBF# ==========================================================================
#  CONFIGURAÇÃO
#  Use a connection string de um usuário SÓ COM PERMISSÃO DE INSERT
#  (veja o SQL no final do arquivo). Prefira definir a variável de ambiente
#  NEON_CONNECTION_STRING na máquina em vez de deixar a senha no script.
#  Formato: postgresql://usuario:senha@ep-xxxx.sa-east-1.aws.neon.tech/neondb?sslmode=require
# ==========================================================================
$script:NeonConnectionString = if ($env:NEON_CONNECTION_STRING) {
    $env:NEON_CONNECTION_STRING
} else {
    'postgresql://USUARIO:SENHA@ep-xxxx.sa-east-1.aws.neon.tech/neondb?sslmode=require'
}

# PowerShell 5.1 pode vir com TLS antigo por padrão
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12


# --------------------------------------------------------------------------
#  Executa UMA instrução SQL no Neon usando o endpoint HTTP (sem driver/DLL).
#  Os valores vão em $Params ($1, $2, ...) e nunca dentro do texto do SQL.
# --------------------------------------------------------------------------
function Invoke-NeonQuery {
    param (
        [Parameter(Mandatory)][string]$ConnectionString,
        [Parameter(Mandatory)][string]$Query,
        [string[]]$Params = @()
    )

    if ($ConnectionString -match '^postgres(?:ql)?://[^@]+@([^/:?]+)') {
        # O endpoint HTTP do Neon exige o host SEM o sufixo -pooler
        $dbHost = $Matches[1] -replace '-pooler$', ''
    } else {
        throw "Connection string do Neon em formato inválido."
    }
    $connHeader = $ConnectionString -replace '(@[^/:?]+?)-pooler', '$1'

    $json  = @{ query = $Query; params = @($Params) } | ConvertTo-Json -Compress -Depth 3
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)   # preserva acentos

    try {
        Invoke-RestMethod -Method Post -Uri "https://$dbHost/sql" `
            -Headers @{ 'Neon-Connection-String' = $connHeader } `
            -Body $bytes -ContentType 'application/json; charset=utf-8' `
            -TimeoutSec 60 -ErrorAction Stop | Out-Null
    }
    catch {
        $detalhe = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        throw "Neon retornou erro: $detalhe"
    }
}


# --------------------------------------------------------------------------
function Send-LogToDatabase {
    [CmdletBinding()]
    param([string]$ConnectionString = $script:NeonConnectionString)

    # Cronômetro
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Registra o resultado (mesmo padrão do seu Write-JsonResult)
    $report = {
        param([bool]$ok, [string]$msg)
        $sw.Stop()
        if (Get-Command Write-JsonResult -ErrorAction SilentlyContinue) {
            Write-JsonResult -Phase "Send-LogToDatabase" -Sucesso $ok -Tempo $sw.Elapsed -Mensagem $msg
        }
    }

    try {
        if (-not $ConnectionString -or $ConnectionString -like '*USUARIO:SENHA*') {
            Show-Header -Text "[ALERTA] Connection string do Neon não configurada." -Color $Yellow
            & $report $false "Connection string do Neon não configurada."
            return
        }

        # Localiza log mais recente
        $agora   = Get-Date
        $ano     = $agora.Year
        $mes     = $agora.Month
        $mesNome = (Get-Culture).DateTimeFormat.MonthNames[$mes - 1]
        $mesFmt  = "{0:D2}. {1}" -f $mes, (Get-Culture).TextInfo.ToTitleCase($mesNome)
        $logLocal = "C:\Protector\Logs\$ano\$mesFmt"

        if (-not (Test-Path $logLocal)) {
            Show-Header -Text "[ALERTA] Diretório de logs não encontrado: $logLocal" -Color $Yellow
            & $report $false "Diretório de logs não encontrado: $logLocal"
            return
        }

        $arquivoLog = Get-ChildItem $logLocal -Filter '*.log' -File |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if (-not $arquivoLog) {
            Show-Header -Text "[ALERTA] Nenhum arquivo .log encontrado em $logLocal" -Color $Yellow
            & $report $false "Nenhum arquivo .log encontrado em $logLocal"
            return
        }

        # Lê o conteúdo (Postgres não aceita caractere NUL em texto)
        $conteudo = Get-Content -LiteralPath $arquivoLog.FullName -Raw -Encoding UTF8
        if ($null -eq $conteudo) { $conteudo = '' }
        $conteudo = $conteudo -replace "`0", ''

        $sql = 'INSERT INTO vistoria_logs (computer_name, ano, mes, arquivo, conteudo) ' +
               'VALUES ($1, $2::int, $3::int, $4, $5)'
        $parametros = @($env:COMPUTERNAME, "$ano", "$mes", $arquivoLog.Name, $conteudo)

        # Envia (até 3 tentativas, caso a rede esteja instável)
        $enviado     = $false
        $ultimoErro  = $null
        $tentativas  = 3
        for ($i = 1; $i -le $tentativas; $i++) {
            try {
                Invoke-NeonQuery -ConnectionString $ConnectionString -Query $sql -Params $parametros
                $enviado = $true
                break
            }
            catch {
                $ultimoErro = $_
                if ($i -lt $tentativas) {
                    Show-Header -Text "[INFO] Falha na tentativa $i de $tentativas. Tentando de novo..." -Color $Yellow
                    Start-Sleep -Seconds (2 * $i)
                }
            }
        }

        if ($enviado) {
            Show-Header -Text "Log '$($arquivoLog.Name)' enviado com sucesso para o banco Neon." -Color $Green
            & $report $true "Log '$($arquivoLog.Name)' enviado ao banco Neon."
        }
        else {
            $msg = $ultimoErro.Exception.Message
            Show-Header -Text "[ERRO] Falha ao enviar log ao banco.`n$msg" -Color $Red
            & $report $false $msg
        }
    }
    catch {
        $msg = $_.Exception.Message
        Show-Header -Text "[ALERTA] Erro inesperado: $msg" -Color $Red
        & $report $false $msg
    }
}


<# ==========================================================================
  SQL PARA RODAR UMA VEZ (SQL Editor do console do Neon, com seu usuário dono)

  CREATE TABLE IF NOT EXISTS vistoria_logs (
      id            BIGSERIAL PRIMARY KEY,
      computer_name TEXT        NOT NULL,
      ano           INT         NOT NULL,
      mes           INT         NOT NULL,
      arquivo       TEXT,
      conteudo      TEXT,
      enviado_em    TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX IF NOT EXISTS idx_vistoria_logs_pc ON vistoria_logs (computer_name, enviado_em DESC);

  -- Usuário usado pelo script: só consegue INSERIR nessa tabela
  CREATE ROLE protector_writer LOGIN PASSWORD 'troque-por-uma-senha-forte';
  GRANT USAGE ON SCHEMA public TO protector_writer;
  GRANT INSERT ON vistoria_logs TO protector_writer;
  GRANT USAGE ON SEQUENCE vistoria_logs_id_seq TO protector_writer;

  -- Último log de cada máquina:
  SELECT DISTINCT ON (computer_name) computer_name, ano, mes, enviado_em, conteudo
  FROM vistoria_logs
  ORDER BY computer_name, enviado_em DESC;
========================================================================== #>

# ---- Uso ------------------------------------------------------------------
# Send-LogToDatabase
# Send-LogToDatabase -ConnectionString 'postgresql://...'