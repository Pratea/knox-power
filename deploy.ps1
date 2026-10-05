# Instala o Knox Power em %USERPROFILE%\Zomboid\mods\KnoxPower.
#   .\deploy.ps1
# So Lua: nao tem nada pra compilar. Feche o jogo antes (mudancas so valem ao reabrir).
param(
    [string]$ZomboidDir = (Join-Path $env:USERPROFILE "Zomboid")
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$src = Join-Path $root "mod\KnoxPower"
$dst = Join-Path $ZomboidDir "mods\KnoxPower"

if (Get-Process ProjectZomboid64 -ErrorAction SilentlyContinue) {
    Write-Warning "O jogo esta aberto: as mudancas so valem depois de reabrir."
}
# /R:2 /W:1: nao trava tentando copiar arquivo em uso (padrao do robocopy e 1 milhao de tentativas)
robocopy $src $dst /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy falhou ($LASTEXITCODE)" }
Write-Host "Knox Power instalado em $dst"
exit 0
