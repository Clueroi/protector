# Protector

O Protector reúne scripts PowerShell para manutenção e inventário de computadores Windows. O fluxo principal organiza as tarefas em fases, registra resultados em log e gera um relatório JSON.

> **Atenção:** algumas rotinas alteram configurações do Windows, removem arquivos, atualizam programas ou criam regras no Firewall. Leia as descrições antes de executar e use uma sessão elevada quando necessário.

## Requisitos

- Windows 10 ou 11.
- Windows PowerShell 5.1 (incluído no Windows 10/11) ou PowerShell 7.
- Privilégios de Administrador para tarefas de manutenção, limpeza, atualização, Firewall e configuração do sistema.
- Acesso à internet para instalação/atualização de componentes e programas.
- `winget` para as rotinas de atualização de aplicativos e Microsoft Store.

## Executar pelo PowerShell

O Agendador de Tarefas **não é necessário** para iniciar o Protector. Abra o PowerShell e execute o iniciador, que usa por padrão o `Protector.ps1` localizado na mesma pasta:

```powershell
Set-Location C:\Protector
.\RodaProtector.ps1
```

Também é possível iniciar diretamente o script principal:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Protector\Protector.ps1
```

O script principal solicita elevação pelo UAC quando necessário. O iniciador não baixa atualizações automaticamente; assim, uma falha de URL do atualizador não impede a execução dos arquivos locais.

## Fluxo principal

O script principal (`Protector.ps1`) define e executa as fases abaixo. As fases podem ser selecionadas ou ignoradas por parâmetro.

| Fase | Atividades |
|---|---|
| 1 — Inventário | Coleta informações de hardware, sistema operacional, rede, discos e programas instalados. |
| 2 — Integridade do sistema | Executa limpeza de componentes, DISM RestoreHealth e SFC. |
| 3 — Otimizações estruturais | Ajusta energia e configura DNS Google nos adaptadores ativos elegíveis. |
| 4 — Limpeza | Limpa cache do Windows Update, arquivos temporários e Lixeiras. |
| 5 — Atualizações do Windows | Atualiza o Windows e os aplicativos da Microsoft Store, se houver internet. |
| 6 — Atualizações de programas | Aplica bloqueios de atualização configurados no Firewall e atualiza programas via Winget. |
| 7 — Pós-atualização | Executa a limpeza de componentes antigos do Windows via DISM. |
| 8 — Armazenamento | Otimiza SSDs e desfragmenta HDDs detectados. |
| 9 — Segurança | Executa uma verificação rápida com o Microsoft Defender. |

O script cria logs em `Logs\<ano>\<mês>` e um JSON de resultados em `Json\<ano>\<mês>`. O envio do log para um servidor de arquivos está disponível por função, mas sua chamada no orquestrador está comentada nesta versão.

### Parâmetros do orquestrador

| Parâmetro | Descrição |
|---|---|
| `-ExecutaFases` | Executa somente as fases indicadas. Exemplo: `-ExecutaFases 1,3,8`. |
| `-PulaFases` | Ignora as fases indicadas. Exemplo: `-PulaFases 4,7`. |
| `-LogLevel` | Nível de log: `INFO`, `WARN`, `ERROR` ou `DEBUG`. |
| `-Simulado` | Modo de ensaio: não executa as ações das etapas. |
| `-FileServer` | Hostname ou IP do servidor de arquivos. A função de envio existe, mas a chamada ao final está desativada no script principal. |
| `-Cliente` | Nome do cliente gravado nos resultados. |

## Funções de manutenção

As funções abaixo estão nos arquivos da pasta `Functions`.

### Inventário e integridade

| Função | O que faz |
|---|---|
| `Get-SystemInventory` | Coleta nome do computador, usuário, Windows, CPU, placa-mãe, número de série, RAM, GPU, rede, partições, saúde dos discos e softwares instalados. Também sinaliza espaço livre inferior a 20 GB no disco C: e alertas de saúde/SMART. |
| `Repair-SystemIntegrity` | Executa limpeza de componentes com DISM, DISM RestoreHealth e `sfc /scannow`; registra códigos de saída e verifica se há reinicialização pendente. Aceita `-SourcePath` para informar uma fonte ao DISM. |
| `Scan-AntiMalware` | Atualiza as definições do Microsoft Defender e executa uma verificação rápida. Requer privilégios de Administrador. |

### Otimização

| Função | O que faz |
|---|---|
| `Optimize-PowerSettings` | Ativa o plano de alto desempenho, ajusta suspensão seletiva USB e tempos limite de energia e desativa a hibernação. Aplica valores diferentes para alimentação AC e, quando há bateria, DC. |
| `Optimize-NetworkSettings` | Configura DNS Google (`8.8.8.8` e `8.8.4.4`) nos adaptadores ativos, exceto os identificados como virtuais, Bluetooth, VPN ou similares. |
| `Optimize-SSD` | Otimiza volumes NTFS/ReFS elegíveis com ReTrim; usa `defrag.exe` como alternativa quando necessário. |
| `Optimize-HDD` | Identifica discos físicos e desfragmenta os volumes de HDD com letra atribuída. Ignora SSDs. |

### Limpeza

| Função | O que faz |
|---|---|
| `Clear-TempFiles` | Executa a limpeza de componentes DISM, remove arquivos de pastas temporárias do Windows e dos usuários, arquivos Prefetch com mais de sete dias e esvazia a Lixeira. Requer Administrador. |
| `Clear-WindowsUpdateCache` | Para serviços relacionados ao Windows Update, limpa o conteúdo de `SoftwareDistribution` e `catroot2` e tenta iniciar os serviços novamente. Requer Administrador. |
| `Clear-AllRecycleBins` | Remove itens das Lixeiras de todas as unidades locais fixas. Requer Administrador. |
| `Clear-BrowserCache` | Fecha Chrome, Edge e Firefox e remove diretórios de cache reconhecidos nesses navegadores. |
| `Clear-RecentFilesHistory` | Remove os atalhos e itens da pasta Itens Recentes do usuário atual. |
| `Remove-OldUpdateFiles` | Executa `DISM /Online /Cleanup-Image /StartComponentCleanup /NoRestart` para limpar componentes antigos do Windows. |

`Clear-BrowserCache` e `Clear-RecentFilesHistory` estão disponíveis como scripts separados, mas não fazem parte das etapas habilitadas no fluxo principal desta cópia.

### Atualizações e Firewall

| Função | O que faz |
|---|---|
| `Update-WindowsOS` | Instala o módulo `PSWindowsUpdate` se necessário e instala atualizações do Windows sem reiniciar automaticamente. |
| `Update-MicrosoftStore` | Usa Winget com a fonte `msstore` para procurar e instalar atualizações da Microsoft Store. |
| `Update-WingetApps` | Executa `winget upgrade --all` em modo silencioso para atualizar aplicativos compatíveis. |
| `Block-AppUpdates` | Localiza executáveis de aplicativos configurados e cria regras de bloqueio no Firewall do Windows. Aceita `-AppNames`, `-ExecutablePaths` e `-AlsoInbound`; oferece `-WhatIf` por suportar `ShouldProcess`. Requer Administrador. |

`Block-AppUpdates` possui perfis específicos para QGIS e Google e procura automaticamente programas/jogos para os demais nomes. A lista padrão e os perfis são configurados no próprio arquivo da função.

### Interface, resultados e logs

| Função | O que faz |
|---|---|
| `Show-ProtectorUI` | Exibe a janela inicial do Protector com texto informativo, cliente, fase atual e barra de progresso. |
| `Show-ProtectorEndUI` | Exibe a tela de conclusão e a fecha automaticamente após alguns segundos. |
| `Write-JsonResult` | Monta e retorna um objeto de resultado com fase, status, duração e mensagem; também registra a mensagem em log se `Write-Log` estiver disponível. |
| `Send-LogToServer` | Localiza o log mais recente do mês e tenta copiá-lo para um compartilhamento SMB do servidor informado. Registra o resultado quando `Write-JsonResult` está disponível. |
| `Update-ProtectorFiles` | Baixa os scripts e assets listados no atualizador para `C:\Protector`, preservando os arquivos locais que não constam na lista. |

## Funções auxiliares

São funções internas de apoio — normalmente não são etapas de manutenção independentes.

### No orquestrador (`Protector.ps1`)

| Função | Finalidade |
|---|---|
| `Ajusta-Fases` | Normaliza os valores de `ExecutaFases` e `PulaFases`. |
| `Get-StepLabel` | Traduz nomes técnicos de etapas para descrições amigáveis. |
| `Write-Report` | Acrescenta texto ao arquivo de log/relatório. |
| `Write-Log` | Aplica o nível configurado, escreve mensagens no console e controla o que é gravado no log. |
| `Show-Header`, `Show-Phase`, `Show-StepStart`, `Show-StepEnd` | Exibem cabeçalhos, fases e estado de início/conclusão das etapas. |
| `Test-IsAdmin`, `Test-AdminOrExit` | Verificam a elevação e encerram a execução quando ela é obrigatória e não está presente. |
| `Initialize-Pwsh7` | Verifica a versão do PowerShell e tenta instalar/reiniciar em PowerShell 7 quando necessário. |
| `Start-Logging`, `Stop-Logging` | Iniciam e finalizam o registro da execução. |
| `Get-RebootPending` | Verifica indicadores de reinicialização pendente no Windows. |
| `Test-Internet` | Verifica conectividade usando uma solicitação de ping. |
| `Get-PhysicalDisksByType` | Lista discos físicos e tenta determinar se são SSD ou HDD, usando WMI como alternativa. |
| `Format-Elapsed`, `Format-HumanTime` | Formata durações para exibição. |
| `Invoke-ProtectorStep` | Executa uma etapa, cronometra, captura erros e armazena o resultado para o resumo/JSON. |
| `DoEvents` | Processa eventos da interface Windows Forms durante a execução. |
| `Get-ConsoleInputMode`, `Set-ConsoleInputMode` | Leem e alteram o modo de entrada do console. |
| `Enable-QuickEditProtection`, `Disable-QuickEditProtection` | Desativam temporariamente a seleção Quick Edit durante o processo e restauram o modo ao sair. |
| `Invoke-QuickEditLog`, `Invoke-ConsoleLog` | Encaminham mensagens auxiliares para o logger quando disponível. |
| `Test-HasRawUI` | Verifica se o host expõe a interface RawUI do console. |
| `Expand-ConsoleWindow` | Tenta maximizar a janela do console e ajustar seu buffer. |
| `Enable-ConsoleAppearance`, `Disable-ConsoleAppearance` | Aplicam e restauram a aparência do console. |

`Format-HumanTime` e `DoEvents` aparecem em mais de um ponto/versão do código; são descritos uma vez aqui.

### Auxiliares das funções de manutenção

| Função | Arquivo/uso |
|---|---|
| `Add-BlockRule` | Cria regra de bloqueio de entrada/saída no Firewall; tenta `netsh` se o cmdlet de Firewall falhar. |
| `Get-SteamLibraries` | Localiza diretórios de bibliotecas Steam a partir da instalação e do arquivo `libraryfolders.vdf`. |
| `Resolve-AppTargets` | Resolve pastas e padrões de executáveis a bloquear para um aplicativo. |
| `Test-PendingReboot` | Verifica indicadores de reinicialização pendente para `Repair-SystemIntegrity`. |
| `Get-RegUninstallNames` | Coleta nomes de aplicativos instalados nas visões de registro 32 e 64 bits. |
| `Remove-OuterQuotes` | Remove aspas duplas externas de uma string no tratamento do JSON. |
| `Show-Header`, `Fail` | Exibem cabeçalho formatado e tratam falhas no atualizador de arquivos. |
| `Write-Log` (fallback) | Função vazia usada em alguns scripts quando o logger principal não está carregado. |

## Scripts de inicialização e utilitários

| Script | Finalidade |
|---|---|
| `Protector.ps1` | Orquestra fases, carrega as funções, produz resumo, log e JSON. |
| `Protector (bom).ps1` | Cópia/variante do orquestrador; não representa uma função adicional. |
| `RodaProtector.ps1` | Inicia o script principal local com os parâmetros recebidos. Usa o `Protector.ps1` da mesma pasta por padrão e não depende do Agendador de Tarefas nem do download automático do atualizador. |
| `ElevaProtector.ps1` | Prepara credenciais e argumentos e inicia o processo do Protector com as credenciais configuradas. |
| `Prepara.ps1` | Prepara o ambiente: Winget, PowerShell 7, PATH, alias, associação de `.ps1` e política de execução; também remove itens antigos específicos. |
| `CriaCredenciais.ps1` | Solicita credenciais, cria uma chave AES se necessário e salva a senha criptografada e o usuário em XML. Proteja o arquivo de chave e o XML. |
| `Atualiza.ps1` | Tenta atualizar scripts e imagens da instalação em `C:\Protector`; a execução do atualizador é separada do iniciador. |
| `Optimize-JsonReport.ps1` | Trata o JSON de inventário: normaliza mensagens, separa hardware/software, estrutura redes, armazenamento e partições e salva o resultado tratado. |
| `Optimize-JsonReport - Copia.ps1` | Cópia/variante do script de tratamento JSON; não é uma função adicional do fluxo principal. |

### Auxiliares dos scripts de inicialização

| Função | Onde é usada |
|---|---|
| `Show-Header`, `Fail` | `RodaProtector.ps1` e `ElevaProtector.ps1`: exibem mensagens formatadas e encerram a execução em falhas de inicialização. |
| `Step` | `Prepara.ps1`: exibe cada etapa da preparação do ambiente. |
| `Test-Winget` | `Prepara.ps1`: verifica se Winget está disponível. |
| `Show-ProgressBar` | `Prepara.ps1`: exibe o progresso da instalação do PowerShell 7. |
| `StatusLine` | `Prepara.ps1`: apresenta o resultado de cada configuração executada. |
| `Show-Header`, `Fail` | `Atualiza.ps1`: exibem o andamento e tratam falhas críticas no download. |

## Limitações e observações desta cópia

- O script principal espera os arquivos carregados em uma subpasta `Functions`; mantenha essa pasta junto de `Protector.ps1`.
- Os endereços de download configurados nos scripts de atualização desta cópia não estão no formato esperado pelo GitHub Raw. O `RodaProtector.ps1` não executa mais essa atualização automaticamente; revise as URLs antes de executar `Atualiza.ps1` ou `Update-ProtectorFiles`.
- O orquestrador referencia `Confirm-MacriumBackup`, mas esse script/função não está presente nesta cópia. A confirmação é opcional no código principal.
- O envio do log para servidor está implementado em `Send-LogToServer`, mas a chamada correspondente no fim do orquestrador está comentada.
- O processamento JSON procura arquivos e diretórios em caminhos de instalação específicos. Ao executar fora da instalação esperada, revise os caminhos em `C:\Protector`.
- `Clear-BrowserCache` e `Clear-RecentFilesHistory` estão no repositório, mas não são carregadas/executadas nas fases atualmente habilitadas.
