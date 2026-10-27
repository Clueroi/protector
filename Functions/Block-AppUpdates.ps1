\xEF\xBB\xBF# ==========================================================================
#  LISTA DE APPS PARA NÃO ATUALIZAR   <-- é só editar aqui
#  Pode ser o nome do programa, da pasta ou do jogo (ex.: 'google', 'undertale')
# ==========================================================================
$script:AppsToBlock = @(
    'qgis'
    'google'
    'undertale'
)

# ==========================================================================
#  PERFIS MANUAIS (opcional)
#  Para apps que você quer controlar com precisão. Se o nome NÃO estiver
#  aqui, o script usa a busca automática (registro + pastas + bibliotecas
#  de jogos) e decide sozinho se é app ou jogo.
#    Match = nome como aparece em "Programas e Recursos" (aceita curinga)
#    Roots = pastas extras onde procurar
#    Exe   = executáveis que serão bloqueados
# ==========================================================================
$script:AppProfiles = @{
    'qgis'   = @{
        Match = @('*QGIS*', '*OSGeo4W*')
        Roots = @('C:\OSGeo4W64', 'C:\OSGeo4W')
        Exe   = @('qgis*-bin.exe', 'maintenancetool.exe', 'osgeo4w-setup*.exe')
    }
    'google' = @{
        Match = @('*Google Chrome*', '*Google Update*')
        Roots = @(
            "${env:ProgramFiles(x86)}\Google\Update",
            "$env:ProgramFiles\Google\Update",
            "$env:LOCALAPPDATA\Google\Update"
        )
        Exe   = @('GoogleUpdate.exe')
    }
}

# Caminhos que indicam que a pasta pertence a um jogo
$script:GamePathPattern = '\\steamapps\\common\\|\\Epic Games\\|\\GOG Games\\|\\GOG Galaxy\\Games\\|\\Games\\'


# --------------------------------------------------------------------------
function Add-BlockRule {
    param (
        [string]$DisplayName,
        [string]$Program,
        [string]$Direction
    )

    if (Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue) {
        Write-Host "Regra '$DisplayName' já existe. Pulando criação."
        return
    }

    try {
        New-NetFirewallRule -DisplayName $DisplayName -Direction $Direction -Action Block `
            -Program $Program -Profile Any -ErrorAction Stop | Out-Null
        Write-Host "Regra '$DisplayName' criada com sucesso."
    }
    catch {
        Write-Host "Tentando fallback para netsh para '$DisplayName'..."
        $dir = if ($Direction -eq 'Outbound') { 'out' } else { 'in' }
        & netsh advfirewall firewall add rule "name=$DisplayName" "dir=$dir" action=block "program=$Program" profile=any | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Regra '$DisplayName' criada via netsh."
        } else {
            Write-Host "Falha ao criar regra '$DisplayName' via netsh."
        }
    }
}

# --------------------------------------------------------------------------
function Get-SteamLibraries {
    $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
    if (-not $steam) {
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    }
    if (-not $steam -or -not (Test-Path -LiteralPath $steam)) { return }

    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $libs += ($m.Groups[1].Value -replace '\\\\', '\')
        }
    }

    foreach ($lib in ($libs | Select-Object -Unique)) {
        $common = Join-Path $lib 'steamapps\common'
        if (Test-Path -LiteralPath $common) { [IO.Path]::GetFullPath($common) }
    }
}

# --------------------------------------------------------------------------
# Dado um nome ("google", "undertale"...), devolve as pastas e os padrões de
# executáveis que devem ser bloqueados.
# --------------------------------------------------------------------------
function Resolve-AppTargets {
    param([Parameter(Mandatory)][string]$Name)

    $updaterPatterns = @('*update*.exe', 'maintenancetool.exe')
    $isProfile = $script:AppProfiles.ContainsKey($Name)
    $prof      = if ($isProfile) { $script:AppProfiles[$Name] }
    $matchList = if ($isProfile) { $prof.Match } else { @("*$Name*") }
    $folders   = New-Object System.Collections.Generic.List[string]

    # 1) Registro (Programas e Recursos)
    $registryRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $registryRoots) {
        foreach ($sub in @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue
            if (-not $p.DisplayName) { continue }

            $hit = $false
            foreach ($m in $matchList) { if ($p.DisplayName -like $m) { $hit = $true; break } }
            if (-not $hit) { continue }

            $loc = $p.InstallLocation
            if (-not $loc -and $p.DisplayIcon) {
                $icon = $p.DisplayIcon -replace '^"?([^",]+).*$', '$1'
                $loc  = Split-Path -Path $icon -Parent
            }
            if (-not $loc -and $p.UninstallString -and $p.UninstallString -notlike 'msiexec*') {
                $u = $p.UninstallString.Trim()
                if ($u.StartsWith('"')) { $u = $u.TrimStart('"').Split('"')[0] }
                $loc = Split-Path -Path $u -Parent
                if ($loc -like '*\uninstall') { $loc = Split-Path -Path $loc -Parent }
            }
            if ($loc -and (Test-Path -LiteralPath $loc)) { $folders.Add($loc) }
        }
    }

    # 2) Pastas extras do perfil
    if ($isProfile -and $prof.Roots) {
        foreach ($r in $prof.Roots) {
            if (Test-Path -LiteralPath $r) { $folders.Add($r) }
        }
    }

    # 3) Busca automática por nome de pasta (apenas se não houver perfil)
    if (-not $isProfile) {
        $scanRoots = @(
            $env:ProgramFiles, ${env:ProgramFiles(x86)},
            "$env:LOCALAPPDATA\Programs", $env:LOCALAPPDATA, $env:APPDATA,
            "$env:ProgramFiles\Epic Games", "${env:ProgramFiles(x86)}\Epic Games",
            'C:\GOG Games', "${env:ProgramFiles(x86)}\GOG Galaxy\Games",
            'C:\Games', 'D:\Games'
        ) + @(Get-SteamLibraries)

        foreach ($r in $scanRoots) {
            if (-not $r -or -not (Test-Path -LiteralPath $r)) { continue }
            Get-ChildItem -LiteralPath $r -Directory -Filter "*$Name*" -ErrorAction SilentlyContinue |
                ForEach-Object { $folders.Add($_.FullName) }
        }
    }

    foreach ($f in ($folders | Sort-Object -Unique)) {
        $full   = [IO.Path]::GetFullPath($f)
        $isGame = $full -match $script:GamePathPattern
        $patterns = if ($isProfile) { $prof.Exe }
                    elseif ($isGame) { @('*.exe') }          # jogo: bloqueia todos os .exe
                    else { $updaterPatterns }                # app: só updaters
        [pscustomobject]@{ Folder = $full; IsGame = $isGame; Patterns = $patterns }
    }
}

# --------------------------------------------------------------------------
function Block-AppUpdates {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$AppNames = $script:AppsToBlock,
        [Parameter(Mandatory = $false)]
        [string[]]$ExecutablePaths,
        [Parameter(Mandatory = $false)]
        [switch]$AlsoInbound
    )

    # === Cronômetro da função ===
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
            function Write-Log { param([string]$Message) }
        }

        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw "Este script deve ser executado como Administrador para criar regras de firewall."
        }

        if (-not $AppNames -and -not $ExecutablePaths) {
            throw "Nenhum app informado. Edite a lista `$AppsToBlock ou use -AppNames / -ExecutablePaths."
        }

        $firewallService = Get-Service -Name MpsSvc -ErrorAction SilentlyContinue
        if ($firewallService -and $firewallService.Status -ne 'Running') {
            Start-Service -Name MpsSvc
            Write-Host "Serviço de Firewall do Windows iniciado."
        }

        # ============================================
        # Descobre os executáveis de cada app
        # ============================================
        $executables = @()

        foreach ($name in $AppNames) {
            $found = 0
            foreach ($t in @(Resolve-AppTargets -Name $name)) {
                $tipo = if ($t.IsGame) { 'jogo' } else { 'app' }
                Write-Host "[$name] pasta encontrada ($tipo): $($t.Folder)"

                foreach ($pattern in $t.Patterns) {
                    $files = Get-ChildItem -LiteralPath $t.Folder -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue
                    foreach ($file in $files) {
                        $executables += [pscustomobject]@{ App = $name; Path = $file.FullName }
                        $found++
                    }
                }
            }
            if ($found -eq 0) {
                Write-Host "[$name] nenhum executável encontrado. Pulando."
                Write-Log "Nenhum executável encontrado para '$name'."
            }
        }

        # Caminhos informados manualmente (arquivo = bloqueia direto; pasta = procura updaters)
        foreach ($path in $ExecutablePaths) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $executables += [pscustomobject]@{ App = 'MANUAL'; Path = (Resolve-Path -LiteralPath $path).Path }
            }
            elseif (Test-Path -LiteralPath $path -PathType Container) {
                foreach ($pattern in @('*update*.exe', 'maintenancetool.exe')) {
                    foreach ($file in (Get-ChildItem -LiteralPath $path -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue)) {
                        $executables += [pscustomobject]@{ App = 'MANUAL'; Path = $file.FullName }
                    }
                }
            }
        }

        $executables = @($executables | Sort-Object -Property Path -Unique)

        # ============================================
        # Cria as regras
        # ============================================
        foreach ($e in $executables) {
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($e.Path)
            $label    = $e.App.ToUpper()

            if ($PSCmdlet.ShouldProcess($e.Path, 'Criar regra de bloqueio no firewall')) {
                Add-BlockRule -DisplayName "Bloqueio_Update_${label}_$fileName" -Program $e.Path -Direction 'Outbound'
                if ($AlsoInbound) {
                    Add-BlockRule -DisplayName "Bloqueio_Update_${label}_IN_$fileName" -Program $e.Path -Direction 'Inbound'
                }
            }
        }

        # === Sucesso ===
        $sw.Stop()
        if (Get-Command Write-JsonResult -ErrorAction SilentlyContinue) {
            $res = @{
                Phase    = 'Block-AppUpdates'
                Sucesso  = $true
                Tempo    = $sw.Elapsed
                Mensagem = "Regras aplicadas com sucesso para $($executables.Count) executáveis."
            }
            $global:Results += Write-JsonResult @res
        }
    }
    catch {
        # === Falha ===
        $sw.Stop()
        $erro = $_ | Format-List * -Force | Out-String
        if (Get-Command Write-JsonResult -ErrorAction SilentlyContinue) {
            $res = @{
                Phase    = 'Block-AppUpdates'
                Sucesso  = $false
                Tempo    = $sw.Elapsed
                Mensagem = $erro.Trim()
            }
            $global:Results += Write-JsonResult @res
        } else {
            Write-Error $erro
        }
    }
}

# ---- Exemplos de uso ------------------------------------------------------
# Block-AppUpdates                         # usa a lista $AppsToBlock lá de cima
# Block-AppUpdates -AppNames 'discord'     # só esse app, na hora
# Block-AppUpdates -WhatIf                 # simula: mostra o que acharia, sem criar regras
# Block-AppUpdates -AlsoInbound            # bloqueia também entrada