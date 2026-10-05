# Knox Power

Mod de Project Zomboid (Build 42.21), só Lua, de **quadros de energia**: um
quadro na parede + um gerador energizam o prédio inteiro (todos os cômodos e
andares) ou uma zona desenhada no mapa, com disjuntores pra setorizar e
economizar combustível. Single-player e multiplayer.

O design completo (regras, decisões e o que foi descoberto no código do jogo)
está em [DESIGN.md](DESIGN.md).

## Como funciona

```
 gerador ──► quadro principal ──► quadros secundários ──► disjuntores ──► aparelhos
             (área: prédio ou zona)
```

- **Energia na área inteira** (`KP_Power.lua`): o jogo considera um tile com
  energia se alguma "posição de gerador" registrada no chunk (8×8) dele está a
  até R tiles. O mod registra pontos próprios, **cada um preso a um chunk só**,
  escolhidos pra cobrir a área sem alcançar cômodos de prédios vizinhos.
- **Quadros** (`KP_Panels.lua`): registro em ModData, decidido pelo servidor;
  gerador, liga/desliga da energia, consumo por hora descontado do tanque.
- **Disjuntores** (`KP_Breakers.lua`, `KP_Devices.lua`): mantêm desligado o que
  está num disjuntor desligado; geladeira/freezer desligam de verdade
  (`KP_Fridge.lua`).
- **Zonas** (`KP_Zones.lua`, `KP_ZoneEditor.lua`): retângulos desenhados por
  admin no mapa do mundo; um quadro numa zona alimenta a zona toda.
- **Visual** (`tools/build_art.py`): a partir do modelo do Blockbench em `art/`
  gera o tile isométrico (`.tiles` + `.pack`), a profundidade, os modelos 3D
  de 1ª pessoa (Viewpoint, opcional) e os ícones.

## Estrutura

```
mod/KnoxPower/          o mod (vai pra Zomboid/mods e pra Workshop)
  42/media/lua/         código (shared = servidor e cliente, client = menus/janelas)
  42/media/scripts/     itens e receitas
  common/media/         profundidade do tile + modelos do Viewpoint
art/                    modelo do Blockbench (fonte da arte)
tools/                  build_art.py (arte do jogo), make_preview.py (capa)
workshop/               capa e descrição da Workshop
deploy.ps1              instala em %USERPROFILE%\Zomboid\mods\KnoxPower
workshop.ps1            monta Zomboid\Workshop\KnoxPower pro uploader do jogo
```

## Uso no desenvolvimento

```powershell
python tools\build_art.py      # depois de mudar o modelo em art\
python tools\make_preview.py   # capa da Workshop / poster
.\deploy.ps1                   # com o jogo fechado
.\workshop.ps1                 # depois: jogo > Workshop > Knox Power > enviar
```

Arte do quadro: Pratea (modelo no Blockbench).
