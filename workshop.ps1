# Monta a pasta que o uploader da Workshop do proprio jogo espera:
#   Zomboid\Workshop\KnoxPower\{workshop.txt, preview.png, Contents\mods\KnoxPower\...}
# Depois: abrir o jogo > Workshop (menu principal) > Knox Power > enviar.
# So Lua e imagens: o uploader do jogo aceita (nao precisa de SteamCMD).
#   .\workshop.ps1
param(
    [string]$ZomboidDir = (Join-Path $env:USERPROFILE "Zomboid")
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

$item = Join-Path $ZomboidDir "Workshop\KnoxPower"
$contents = Join-Path $item "Contents\mods\KnoxPower"
New-Item -ItemType Directory -Force $contents | Out-Null
robocopy (Join-Path $root "mod\KnoxPower") $contents /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy falhou ($LASTEXITCODE)" }

# workshop.txt: o uploader acrescenta id=... depois do 1o envio -- preserva.
$txt = Join-Path $item "workshop.txt"
$id = $null
if (Test-Path $txt) { $id = Select-String -Path $txt -Pattern '^id=' | Select-Object -First 1 }
Copy-Item (Join-Path $root "workshop\workshop.txt") $txt -Force
if ($id) { Add-Content -Path $txt -Value $id.Line }
Copy-Item (Join-Path $root "workshop\preview.png") (Join-Path $item "preview.png") -Force

$size = (Get-ChildItem -Recurse $item | Measure-Object -Sum Length).Sum / 1MB
Write-Host ("Pronto pra envio: {0} ({1:N1} MB)" -f $item, $size)
exit 0
