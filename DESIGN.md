# Knox Power -- documento de design

Mod de Project Zomboid (**Build 42.21**), **só em Lua** (sem Java/ZombieBuddy):
quadros de energia que levam a energia de um gerador para um prédio inteiro
(ou uma zona com vários prédios), com disjuntores para setorizar e economizar
combustível. Single-player e multiplayer.

Nome pensando no futuro: reativar subestações e a usina principal para devolver
energia a partes da cidade (ver "Futuro").

---

## 1. Como a energia funciona no Build 42 (pesquisado no código do jogo)

- **Um tile tem energia** se estiver dentro do raio de algum gerador ligado.
  O jogo NÃO guarda "tem energia" no tile: calcula na hora com
  `IsoChunk:isGeneratorPoweringSquare(x, y, z)`, que testa a distância até as
  "posições de gerador" registradas naquele pedaço do mapa
  (`IsoChunk:addGeneratorPos` / `removeGeneratorPos`).
- **Raio:** círculo com o valor da opção de sandbox "Alcance do gerador"
  (`GeneratorTileRange`, padrão 20 tiles), com alcance vertical limitado.
- **Faxina do jogo:** `IsoChunk:checkForMissingGenerators()` apaga posições de
  gerador onde não existe um gerador ligado de verdade.
- **Aparelhos elétricos:** cada um se registra no pedaço do mapa como "objeto
  que usa energia" e informa o gasto atual em
  `IsoObject:getGeneratorPowerConsumption()` (0 quando desligado).
- **Consumo** (tanque do gerador = 10 unidades; gasto por hora de jogo, vezes
  a opção de sandbox "Consumo de combustível do gerador"):

  | O que está ligado | Por hora |
  |---|---|
  | Gerador ligado, sem nada | 0,02 |
  | Lâmpada (interruptor ligado) | 0,002 |
  | Rádio | 0,01 |
  | TV | 0,03 |
  | Bomba de combustível | 0,03 |
  | Carregador de bateria | 0,05 |
  | Geladeira **ou** freezer | 0,08 |
  | Geladeira **com** freezer | 0,13 |
  | Fogão / forno | 0,09 |
  | Lavadora ou secadora | 0,09 |
  | Lava-e-seca empilhada | 0,9 |

  O gerador soma, a cada hora, o gasto dos aparelhos **dentro do raio dele**.
- **Geladeira/freezer:** são reconhecidos pelo **tipo do compartimento**
  (`fridge` / `freezer`): é o que faz gastar energia
  (`getContainerByType`) e gelar/congelar a comida
  (`ItemContainer:isFridge()` / `isFreezer()`, e o `Food` também confere).
  Não têm botão de liga/desliga no jogo.

---

## 2. Conceitos

| Conceito | O que é |
|---|---|
| **Zona** | Área que um sistema de quadros alimenta. Por padrão, **o prédio** onde o quadro está (todos os cômodos e andares). Ou uma **zona predefinida** (retângulos desenhados no mapa, ex: o escritório de Muldraugh, que são 2 prédios). |
| **Quadro principal** | Quadro ligado ao gerador. **Um gerador por quadro principal.** Há **um quadro principal por zona**. |
| **Quadro secundário** | Outros quadros da mesma zona; recebem energia do principal (ex: um por andar/ala). Precisam estar **na mesma zona** -- sem limite de distância. |
| **Disjuntor** | Circuito dentro de um quadro, com nome ("Cozinha", "Quartos"). Liga/desliga todos os aparelhos ligados a ele. |
| **Circuito "Geral"** | Onde ficam os aparelhos da zona que ninguém setorizou. Liga/desliga como um disjuntor. |

Hierarquia: **gerador → quadro principal → quadros secundários → disjuntores → aparelhos**.

---

## 3. Regras

### Quadros
- **Visual próprio (feito):** modelo do autor no Blockbench (`art/fuse_box.*`).
  `tools/build_art.py` gera dele o tile isométrico do mod (`knoxpower_01_0..3`,
  `tiledef=knoxpower 7319` + `KnoxPower.pack`), os modelos 3D de 1ª pessoa
  (pacote próprio registrado no Viewpoint) e os ícones dos itens. Quadros
  instalados com o visual antigo trocam sozinhos. Texto abaixo é histórico.
- **Visual provisório (antigo):** sprite vanilla de caixa elétrica de parede
  `industry_02_212` (parede N), `_213` (W), `_214` (S), `_215` (E) --
  ver `candidatos_quadro.png`. Em 1ª pessoa, o pack Voxel Studio já tem
  modelos 3D para esses 4 sprites. No futuro o autor faz arte própria (tile
  ou modelo 3D): o código isola "qual objeto é o quadro" para a troca não
  mexer no resto.
- Três tamanhos, **mesmo visual** (pelo menos no começo):

  | Tamanho | Disjuntores | Receita |
  |---|---|---|
  | Pequeno | 4 | 1 `SmallSheetMetal` + 3 `ElectricWire` |
  | Médio | 8 | 2 `SmallSheetMetal` + 6 `ElectricWire` |
  | Grande | 12 | 1 `SheetMetal` + 9 `ElectricWire` |

  ("Chapa de metal" = `SmallSheetMetal`; "chapa grande" = `SheetMetal` -- confirmado.)
- **Instalar** numa parede do prédio/zona: botão direito na parede >
  "Instalar quadro de energia". Requer **Eletricidade 3** + chave de fenda.
- **Nome:** dar/renomear pelo menu do quadro.
- **Desinstalar:** devolve **a caixa** (o item do quadro, do mesmo tamanho).
- **Qualquer jogador** pode mexer em qualquer quadro.

### Gerador
- Fica **na mesma zona** do quadro principal. Botão direito no gerador >
  "Conectar ao quadro de energia" (Eletricidade 3 + `ElectricWire`).
- Enquanto o gerador estiver ligado e com combustível, a zona tem energia
  (respeitando os disjuntores).
- O consumo de toda a zona sai do tanque desse gerador.
- Decidido na Fase 3: o gerador precisa estar a **até 12 tiles** da área do
  quadro (prédio ou zona). Fase 5: vários quadros por área -- o primeiro é o
  principal (gerador), os outros são secundários; se o principal sai, o
  secundário mais antigo assume.
- Fase 5, área de uma zona = chão dos retângulos (andar 0) + todos os andares
  de todo prédio que encosta neles. Editor: botão "Knox Power: zonas" no mapa
  (permissão CanSetupNonPVPZone; single-player liberado). O gerador continua precisando estar
  "conectado" do jeito normal do jogo pra poder ser ligado.

### Setorizar aparelhos
- Com **chave de fenda na mão**, botão direito num aparelho >
  **Elétrica > Ligar ao disjuntor...** (lista os disjuntores dos quadros da
  zona). Requer **Eletricidade 3**.
- Vale para: luzes (interruptor), TV, rádio, fogão/forno, lavadora,
  secadora, lava-e-seca, carregador de bateria, bomba de combustível,
  **geladeira e freezer**.

### Disjuntor desligado
- **Aparelhos com botão** (luz, TV, rádio, fogão, lavadora, secadora,
  carregador): o mod desliga e **impede de ligar** enquanto o disjuntor
  estiver desligado (a opção some/fica bloqueada no menu).
- **Geladeira e freezer:** o mod troca o tipo do compartimento
  (`fridge`/`freezer`) por um tipo próprio ("geladeira desligada"). Para o
  jogo vira um armário: **para de gastar e de gelar**; a comida esquenta e
  estraga no ritmo normal. Religou, o tipo volta. Nome do compartimento
  mostra "Geladeira (desligada)".
  - Descoberto na Fase 2: trocar o tipo **não basta** pra parar de gelar --
    `isFridge()` também é verdadeiro se o sprite tem a propriedade
    `IsFridge` (quase toda geladeira tem). Por isso o mod também força
    `customTemperature` = 1.0 (ambiente), que tem prioridade sobre tudo em
    `getTemperature()`. Esse valor não é salvo: é reaplicado quando o chunk
    carrega, olhando só o tipo trocado (`KP_Fridge.lua`).
  - Pegar/desmontar a geladeira desligada: o mod restaura o tipo antes.

### Consumo
- O mod soma `getGeneratorPowerConsumption()` dos aparelhos da zona que
  **não** estão no raio do próprio gerador (esses o jogo já cobra) e
  desconta do tanque, por hora de jogo, com o mesmo multiplicador de sandbox.

### Obtenção
- **Encontrar:** lojas de construção/ferragens e fábricas -- **pouco, mas
  quase certo** (um ou outro por lugar, não pilhas); garagens: **~1 em cada
  100 garagens**. Tabelas de loot candidatas: `ToolStoreMisc`,
  `ToolStoreTools`, `CrateElectronics`, `WireFactoryElectric`,
  `ToolFactoryTools`, `RadioFactoryComponents`; garagem: `GarageTools`,
  `GarageMetalwork`.
- **Fabricar:** receitas acima.

---

## 4. Como funciona por dentro

### Energia na zona inteira ("pontos de energia")
- O quadro principal, com o gerador ligado, registra **pontos de energia** nos
  pedaços do mapa da zona (`chunk:addGeneratorPos`), posicionados para cobrir
  todos os tiles da zona com o **mínimo de sobra** (cada ponto alcança um
  círculo com o raio do gerador).
- **Limitação:** a cobertura é por círculo, não pelas paredes -- um vizinho
  colado pode receber energia junto (igual ao gerador vanilla hoje).
- Como o jogo apaga posições sem gerador de verdade, o mod **reaplica** os
  pontos quando um pedaço do mapa carrega e periodicamente, enquanto o
  gerador estiver ligado. Gerador desligado/sem combustível: remove tudo.

### Zonas predefinidas
- **Editor no mapa-múndi** (só admin / modo debug): arrastar retângulos,
  dar nome, salvar. Arquivo `Zomboid/Lua/KnoxPower/zonas.lua`.
- As zonas feitas pelo autor vão **dentro do mod** como padrão; servidores
  podem ter zonas próprias.
- Quadro instalado dentro de uma zona predefinida alimenta a zona inteira;
  fora de qualquer zona, alimenta o prédio onde está.

### Multiplayer
- **Servidor é a autoridade:** quadros, disjuntores, ligações de aparelhos e
  zonas ficam num ModData global salvo com o mundo.
- Os clientes recebem o estado e aplicam as mesmas regras localmente (pontos
  de energia, geladeiras desligadas, aparelhos bloqueados) -- luzes e
  aparelhos aparecem iguais para todos.
- Single-player: mesmo código (como no KNOX TV, o "servidor" chama o cliente
  direto).

---

## 5. Interface do quadro (HUD)

Abrir: botão direito no quadro > "Abrir quadro".

- Nome do quadro (editável), tamanho, se é principal ou secundário.
- **Principal:** gerador conectado, combustível (%), consumo atual/hora,
  **tempo restante** estimado.
- **Disjuntores** (até 4/8/12): nome, liga/desliga, consumo, nº de aparelhos.
  Adicionar/renomear/remover disjuntor.
- Circuito "Geral" e totais da zona.
- Botão "Desligar tudo" / disjuntor geral.

---

## 6. Futuro (fora do escopo agora)

- **Subestações e usina principal:** reativar para devolver energia à
  cidade. Religar a cidade inteira é simples (a energia da cidade é um
  interruptor global do mundo); religar só uma região usaria o mesmo sistema
  de pontos de energia em escala maior e precisa de estudo de desempenho.
- Arte própria para os quadros (tile novo), um visual por tamanho.
- Baterias / banco de energia.

---

## 7. Plano de implementação (fases, risco primeiro)

1. **Prova de conceito da energia:** pontos de energia via Lua levando luz a
   um prédio inteiro a partir de um gerador (incluindo reaplicação após a
   faxina do jogo). É a parte mais arriscada -- testar antes de tudo.
2. **Prova de conceito da geladeira:** troca de tipo do compartimento
   (para de gelar/gastar, volta ao religar, desmontar com segurança).
3. **Quadros e gerador:** itens, receitas, loot, instalar na parede, conectar
   gerador, zona = prédio, consumo descontado do tanque.
4. **Disjuntores e setorização:** HUD do quadro, ligar aparelhos com chave de
   fenda, bloquear aparelhos com disjuntor desligado.
5. **Quadros secundários** e **zonas predefinidas** (editor no mapa).
6. **Multiplayer** completo + testes com amigos.
7. Publicação na Workshop (passa no uploader do jogo -- só Lua e imagens).

---

## A confirmar

- (nada pendente -- design fechado)
