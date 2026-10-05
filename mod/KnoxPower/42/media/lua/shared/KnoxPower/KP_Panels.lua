-- Knox Power - quadros de energia (Fase 3): registro, gerador, energia e consumo.
--
-- Quem decide e o SERVIDOR (ou o proprio jogo em single-player):
--   * a lista de quadros fica em ModData ("KnoxPower_Panels") e vai pra todos
--     os clientes com ModData.transmit sempre que muda;
--   * o servidor confere de tempos em tempos se o gerador de cada quadro esta
--     ligado e com combustivel -> liga/desliga os pontos de energia do predio;
--   * a cada hora de jogo, desconta do tanque o consumo dos aparelhos do
--     predio que estao FORA do alcance do proprio gerador (os de dentro o
--     jogo ja cobra sozinho).
-- Os clientes so aplicam os pontos dos quadros energizados no mapa local
-- (pra luz e aparelhos aparecerem ligados) e mostram o menu (KP_PanelMenu.lua).

require "KnoxPower/KP_Power"
require "KnoxPower/KP_Zones"

local KP = KnoxPower
KP.Panels = KP.Panels or {}
local Panels = KP.Panels

Panels.MODDATA = "KnoxPower_Panels"
Panels.MODULE = "KnoxPower"
Panels.MIN_ELECTRICITY = 3
--- Formato dos pontos de energia (2 = cada ponto preso a um chunk, sem vazar;
--- 3 = protege tambem o tile em volta dos vizinhos e o chao de zona colado)
Panels.POINTS_VERSION = 3
--- Distancia maxima (em tiles) do gerador ate o predio do quadro.
Panels.MAX_GENERATOR_DISTANCE = 12
local CHECK_MS = 2000
local RECONCILE_MS = 5000
--- Horas de consumo cobradas de uma vez no maximo (gerador ficou longe muito tempo).
local MAX_CATCHUP_HOURS = 24 * 7

--- Tamanhos: tipo do item, disjuntores e chave de traducao.
Panels.SIZES = {
    Small = { item = "KnoxPower.PowerPanelSmall", breakers = 4 },
    Medium = { item = "KnoxPower.PowerPanelMedium", breakers = 8 },
    Large = { item = "KnoxPower.PowerPanelLarge", breakers = 12 },
}
Panels.SIZE_ORDER = { "Small", "Medium", "Large" }

--- Sprite do quadro por parede: tile proprio do mod (knoxpower.tiles +
--- KnoxPower.pack, gerados por tools/build_art.py a partir do modelo em art/).
--- N/W: parede no proprio tile; S/E: parede no tile vizinho (sul/leste).
Panels.SPRITES = { N = "knoxpower_01_0", W = "knoxpower_01_1", S = "knoxpower_01_2", E = "knoxpower_01_3" }
Panels.DIR_ORDER = { "N", "W", "S", "E" }

function Panels.sizeOfItem(fullType)
    for size, def in pairs(Panels.SIZES) do
        if def.item == fullType then return size end
    end
    return nil
end

--- Quem decide: servidor ou single-player.
function Panels.isAuthority()
    return not isClient()
end

local function notBroken(item)
    return not item:isBroken()
end

function Panels.hasSkill(character)
    return character:getPerkLevel(Perks.Electricity) >= Panels.MIN_ELECTRICITY
end

function Panels.hasScrewdriver(character)
    return character:getInventory():containsTagEvalRecurse(ItemTag.SCREWDRIVER, notBroken)
end

--- Eletricidade 3 + chave de fenda inteira no inventario.
function Panels.hasRequirements(character)
    return Panels.hasSkill(character) and Panels.hasScrewdriver(character)
end

-- ---------------------------------------------------------------------------
-- Registro (ModData)
-- ---------------------------------------------------------------------------

function Panels.data()
    local data = ModData.getOrCreate(Panels.MODDATA)
    data.panels = data.panels or {}
    data.nextId = data.nextId or 1
    return data
end

--- Quadros indexados por id em texto.
function Panels.all()
    return Panels.data().panels
end

function Panels.get(id)
    return id and Panels.all()[tostring(id)] or nil
end

local function transmit()
    if isServer() then ModData.transmit(Panels.MODDATA) end
end

-- ---------------------------------------------------------------------------
-- Area, principal e secundarios (Fase 5)
--
-- Area = o que o quadro alimenta: a zona predefinida que encosta no predio
-- (KP_Zones.lua) ou, fora de zona, o proprio predio. panel.buildingKey guarda
-- a chave da AREA ("zone:<id>" ou o canto do predio). Na mesma area, o
-- primeiro quadro e o PRINCIPAL (gerador + pontos de energia); os outros sao
-- SECUNDARIOS: so tem disjuntores e recebem a energia do principal.
-- ---------------------------------------------------------------------------

--- Quadros antigos (antes da Fase 5) nao tem o campo: eram todos principais.
function Panels.isMain(panel)
    return panel.main ~= false
end

--- Principal da area, se houver.
function Panels.mainOfArea(key)
    for _, p in pairs(Panels.all()) do
        if p.buildingKey == key and Panels.isMain(p) then return p end
    end
    return nil
end

--- Principal de onde o quadro recebe energia (ele mesmo, se for principal).
function Panels.mainOf(panel)
    if Panels.isMain(panel) then return panel end
    return Panels.mainOfArea(panel.buildingKey)
end

--- Quadros da mesma area, principal primeiro e depois por ordem de instalacao.
function Panels.panelsOfArea(key)
    local list = {}
    for _, p in pairs(Panels.all()) do
        if p.buildingKey == key then table.insert(list, p) end
    end
    table.sort(list, function(a, b)
        if Panels.isMain(a) ~= Panels.isMain(b) then return Panels.isMain(a) end
        return a.id < b.id
    end)
    return list
end

--- Area a partir do predio: zona (se ele encosta numa) ou o proprio predio.
--- Devolve chave, retangulos e o id da zona (ou nil).
function Panels.areaFor(def, x, y)
    local rects = KP.buildingRects(def)
    if #rects == 0 then return nil end
    local zone = KP.Zones and KP.Zones.zoneFor(x, y, rects)
    if zone then return "zone:" .. zone.id, KP.Zones.area(zone), zone.id end
    return KP.Zones.buildingKey(rects), rects, nil
end

--- Quadro com esse gerador, se houver.
function Panels.panelOfGenerator(x, y, z)
    for _, p in pairs(Panels.all()) do
        if p.gen and p.gen.x == x and p.gen.y == y and p.gen.z == z then return p end
    end
    return nil
end

--- Distancia (em tiles, no plano) de um ponto ate o retangulo mais perto do predio.
function Panels.distanceToBuilding(panel, x, y)
    local best = math.huge
    for _, r in ipairs(panel.rects) do
        local dx = math.max(r.x - x, 0, x - (r.x + r.w - 1))
        local dy = math.max(r.y - y, 0, y - (r.y + r.h - 1))
        best = math.min(best, math.sqrt(dx * dx + dy * dy))
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Objetos do mapa
-- ---------------------------------------------------------------------------

--- Paredes onde da pra prender um quadro a partir deste tile: lista de "N"/"W"/"S"/"E".
function Panels.wallsOf(sq)
    local dirs = {}
    local cell = getCell()
    if sq:getWall(true) then table.insert(dirs, "N") end
    if sq:getWall(false) then table.insert(dirs, "W") end
    local south = cell:getGridSquare(sq:getX(), sq:getY() + 1, sq:getZ())
    if south and south:getWall(true) then table.insert(dirs, "S") end
    local east = cell:getGridSquare(sq:getX() + 1, sq:getY(), sq:getZ())
    if east and east:getWall(false) then table.insert(dirs, "E") end
    return dirs
end

--- Deslocamento ate o tile do outro lado de cada parede.
local ACROSS = { N = { 0, -1 }, W = { -1, 0 }, S = { 0, 1 }, E = { 1, 0 } }

--- Predio a que pertence a parede `dir` deste tile: o do proprio tile (quadro
--- do lado de dentro) ou o do tile do outro lado da parede (quadro do lado de fora).
--- Devolve tambem o tile de dentro do predio.
function Panels.buildingOfWall(sq, dir)
    local building = sq:getBuilding()
    if building then return building, sq end
    local d = ACROSS[dir]
    local other = d and getCell():getGridSquare(sq:getX() + d[1], sq:getY() + d[2], sq:getZ())
    if other and other:getBuilding() then return other:getBuilding(), other end
    return nil
end

--- Tile de dentro do predio do quadro (salvo na instalacao; quadros antigos
--- calculam pela posicao e pela parede).
local function homeOf(panel)
    if panel.home then return panel.home end
    local d = ACROSS[panel.dir] or { 0, 0 }
    local metaGrid = getWorld():getMetaGrid()
    if metaGrid:getBuildingAt(panel.x, panel.y) then
        return { x = panel.x, y = panel.y, z = panel.z }
    end
    return { x = panel.x + d[1], y = panel.y + d[2], z = panel.z }
end

--- Id do quadro se o objeto for um quadro do Knox Power.
function Panels.idOfObject(obj)
    if not obj or not obj.hasModData or not obj:hasModData() then return nil end
    return obj:getModData().knoxPanelId
end

--- Objeto do quadro no mapa (nil se o tile nao estiver carregado ou o objeto sumiu).
--- Devolve tambem se o tile esta carregado.
function Panels.objectOf(panel)
    local sq = getCell():getGridSquare(panel.x, panel.y, panel.z)
    if not sq then return nil, false end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if Panels.idOfObject(obj) == panel.id then return obj, true end
    end
    return nil, true
end

--- Gerador conectado ao quadro. Devolve gerador (ou nil) e se o tile esta carregado.
function Panels.generatorOf(panel)
    if not panel.gen then return nil, false end
    local sq = getCell():getGridSquare(panel.gen.x, panel.gen.y, panel.gen.z)
    if not sq then return nil, false end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if instanceof(obj, "IsoGenerator") then return obj, true end
    end
    return nil, true
end

-- ---------------------------------------------------------------------------
-- Pontos de energia (dos dois lados)
-- ---------------------------------------------------------------------------

--- Reaplica os pontos de todos os quadros principais energizados
--- (secundarios nao tem pontos: a area ja e coberta pelo principal).
function Panels.applyAll()
    for _, p in pairs(Panels.all()) do
        if p.powered and Panels.isMain(p) then KP.addPoints(p.points) end
    end
end

--- Tira os pontos de um quadro e reaplica os outros (caso dividam algum ponto).
local function cutPower(panel)
    KP.removePoints(panel.points)
    Panels.applyAll()
    KP.refreshRects(panel.rects)
end

local function givePower(panel)
    KP.addPoints(panel.points)
    KP.refreshRects(panel.rects)
end

--- Cliente: chegou a lista nova do servidor. Corta a energia dos quadros
--- que sairam ou desligaram, troca a lista e aplica a dos energizados.
function Panels.onListReceived(data)
    local old = Panels.all()
    local new = data.panels or {}
    ModData.add(Panels.MODDATA, data)
    -- corta tudo que saiu, desligou, deixou de ser principal ou mudou de area
    local function same(a, b)
        return b and b.powered and Panels.isMain(b) and a.buildingKey == b.buildingKey and #a.points == #b.points
    end
    for id, p in pairs(old) do
        if p.powered and Panels.isMain(p) and not same(p, new[id]) then cutPower(p) end
    end
    for id, p in pairs(new) do
        if p.powered and Panels.isMain(p) and not same(p, old[id]) then givePower(p) end
    end
    Panels.applyAll()
end

-- ---------------------------------------------------------------------------
-- Acoes (so servidor / single-player). Devolvem nil se deu certo, ou a chave
-- de traducao do motivo de nao dar.
-- ---------------------------------------------------------------------------

--- Instala o quadro do item na parede `dir` do tile.
function Panels.install(character, item, sq, dir)
    local size = Panels.sizeOfItem(item:getFullType())
    if not size or not Panels.SPRITES[dir] then return "IGUI_KnoxPower_CantInstall" end
    local building, inside = Panels.buildingOfWall(sq, dir)
    if not building then return "IGUI_KnoxPower_NeedBuilding" end
    local key, rects = Panels.areaFor(building:getDef(), inside:getX(), inside:getY())
    if not key then return "IGUI_KnoxPower_NeedBuilding" end
    -- primeiro quadro da area = principal; os outros recebem energia dele
    local main = Panels.mainOfArea(key) == nil

    local data = Panels.data()
    local id = data.nextId
    data.nextId = id + 1

    local obj = IsoObject.new(sq, Panels.SPRITES[dir], "KnoxPowerPanel")
    obj:getModData().knoxPanelId = id
    sq:AddTileObject(obj)
    obj:transmitCompleteItemToClients()

    local container = item:getContainer()
    if container then
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    end

    data.panels[tostring(id)] = {
        id = id, x = sq:getX(), y = sq:getY(), z = sq:getZ(), dir = dir, size = size,
        name = "", buildingKey = key, rects = rects, main = main,
        home = { x = inside:getX(), y = inside:getY(), z = inside:getZ() },
        points = KP.coverPoints(rects, KP.generatorRadius()), pointsVersion = Panels.POINTS_VERSION,
        powered = false, rate = 0,
        -- Fase 4: disjuntores {name, on}, aparelhos por chave {x,y,z,kind,sprite,breaker}
        -- e a chave geral (desligada = predio inteiro sem energia do quadro)
        breakers = {}, devices = {}, mainOn = true,
    }
    transmit()
    return nil
end

--- Tira o quadro da parede e devolve a caixa pro jogador.
function Panels.uninstall(character, panel)
    local obj = Panels.objectOf(panel)
    if obj then obj:getSquare():transmitRemoveItemFromSquare(obj) end
    if panel.gen then Panels.disconnectGenerator(panel) end
    if panel.powered and Panels.isMain(panel) then cutPower(panel) end
    Panels.all()[tostring(panel.id)] = nil
    -- principal saiu: o secundario mais antigo da area assume (sem gerador)
    if Panels.isMain(panel) then
        local heir = Panels.panelsOfArea(panel.buildingKey)[1]
        if heir then heir.main = true end
    end
    Panels.update()
    local inv = character:getInventory()
    local item = inv:AddItem(Panels.SIZES[panel.size].item)
    if item then sendAddItemToContainer(inv, item) end
    transmit()
    return nil
end

--- Liga o gerador ao quadro (gasta um fio eletrico do jogador).
function Panels.connectGenerator(character, panel, generator)
    local sq = generator:getSquare()
    if not Panels.isMain(panel) then return "IGUI_KnoxPower_NotMain" end
    if Panels.panelOfGenerator(sq:getX(), sq:getY(), sq:getZ()) then return "IGUI_KnoxPower_GeneratorTaken" end
    if panel.gen then return "IGUI_KnoxPower_PanelHasGenerator" end
    if Panels.distanceToBuilding(panel, sq:getX(), sq:getY()) > Panels.MAX_GENERATOR_DISTANCE then
        return "IGUI_KnoxPower_GeneratorTooFar"
    end
    local wire = character:getInventory():getFirstTypeRecurse("Base.ElectricWire")
    if not wire then return "IGUI_KnoxPower_NeedWire" end
    local container = wire:getContainer()
    container:Remove(wire)
    sendRemoveItemFromContainer(container, wire)
    panel.gen = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
    panel.lastHour = math.floor(getGameTime():getWorldAgeHours())
    -- O jogo so deixa ligar gerador "conectado a uma construcao": ligar ao
    -- quadro ja conta como essa conexao. Lembra se fomos nos que conectamos,
    -- pra desfazer so isso ao desconectar.
    if not generator:isConnected() then
        generator:setConnected(true)
        panel.genPlugged = true
    end
    Panels.update()
    transmit()
    return nil
end

function Panels.disconnectGenerator(panel)
    -- se o quadro que conectou o gerador, desliga e desconecta ele tambem
    -- (gerador ligado sem estar conectado a nada ficaria num estado invalido)
    local gen = Panels.generatorOf(panel)
    if gen and panel.genPlugged then
        if gen:isActivated() then
            gen:setActivated(false)
            gen:sync()
        end
        gen:setConnected(false)
    end
    panel.genPlugged = nil
    panel.gen = nil
    panel.lastHour = nil
    panel.rate = 0
    if panel.powered then
        panel.powered = false
        if Panels.isMain(panel) then cutPower(panel) end
    end
    Panels.update()
    transmit()
end

function Panels.rename(panel, name)
    panel.name = tostring(name or ""):sub(1, 40)
    transmit()
end

-- ---------------------------------------------------------------------------
-- Verificacao periodica e consumo (so servidor / single-player)
-- ---------------------------------------------------------------------------

--- Confere objetos e geradores; liga/desliga a energia de cada quadro.
--- So decide sobre o que esta carregado -- longe de todos, mantem o ultimo estado.
function Panels.update()
    local changed = false
    for id, p in pairs(Panels.all()) do
        local obj, loaded = Panels.objectOf(p)
        if loaded and not obj then
            -- quadro sumiu (parede destruida, etc.)
            if p.powered then cutPower(p) end
            Panels.all()[id] = nil
            changed = true
        else
            -- quadro instalado com o visual antigo (caixa vanilla): troca pro tile do mod
            local sprite = obj and obj:getSprite()
            local wanted = Panels.SPRITES[p.dir]
            if sprite and wanted and sprite:getName() ~= wanted then
                obj:setSpriteFromName(wanted)
                if isServer() then obj:transmitUpdatedSpriteToClients() end
            end
            if Panels.isMain(p) and p.pointsVersion ~= Panels.POINTS_VERSION then
                -- pontos do formato antigo (vazavam pros vizinhos): recalcula
                if p.powered then cutPower(p) end
                local key = p.buildingKey or ""
                local zone = key:sub(1, 5) == "zone:" and KP.Zones.get(key:sub(6)) or nil
                if zone then p.rects = KP.Zones.area(zone) end
                p.points = KP.coverPoints(p.rects, KP.generatorRadius())
                p.pointsVersion = Panels.POINTS_VERSION
                if p.powered then givePower(p) end
                changed = true
            end
            if Panels.isMain(p) then
                local gen, genLoaded = Panels.generatorOf(p)
                if p.gen and genLoaded and not gen then
                    -- gerador foi levado embora
                    p.gen = nil
                    p.genPlugged = nil
                    p.lastHour = nil
                    p.rate = 0
                    changed = true
                end
                local powered = p.powered
                if not p.gen or p.mainOn == false then
                    powered = false
                elseif gen then
                    powered = gen:isActivated() and gen:getFuel() > 0
                end
                if powered ~= p.powered then
                    p.powered = powered
                    if powered then givePower(p) else cutPower(p) end
                    changed = true
                end
            end
        end
    end
    -- secundarios: tem energia quando o principal da area tem
    for _, p in pairs(Panels.all()) do
        if not Panels.isMain(p) then
            local main = Panels.mainOf(p)
            if not main then
                p.main = true -- area ficou sem principal: este assume
                changed = true
            end
            local powered = main ~= nil and main.powered == true
            if powered ~= p.powered then
                p.powered = powered
                changed = true
            end
        end
    end
    if changed then transmit() end
end

--- Recalcula a area de todos os quadros (depois de criar/mudar/apagar zona).
--- Na mesma area fica um principal so: o que tem gerador (ou o mais antigo);
--- os outros viram secundarios e perdem o gerador.
function Panels.recomputeAreas()
    local metaGrid = getWorld():getMetaGrid()
    for _, p in pairs(Panels.all()) do
        local home = homeOf(p)
        p.home = home
        local def = metaGrid:getBuildingAt(home.x, home.y)
        local key, rects = nil, nil
        if def then key, rects = Panels.areaFor(def, home.x, home.y) end
        if key and (key ~= p.buildingKey or #rects ~= #p.rects) then
            if p.powered and Panels.isMain(p) then
                cutPower(p)
                p.powered = false
            end
            p.buildingKey = key
            p.rects = rects
            p.points = KP.coverPoints(rects, KP.generatorRadius())
            p.pointsVersion = Panels.POINTS_VERSION
        end
    end
    local areas = {}
    for _, p in pairs(Panels.all()) do
        areas[p.buildingKey] = areas[p.buildingKey] or {}
        table.insert(areas[p.buildingKey], p)
    end
    for _, list in pairs(areas) do
        table.sort(list, function(a, b)
            local ga, gb = a.gen ~= nil and Panels.isMain(a), b.gen ~= nil and Panels.isMain(b)
            if ga ~= gb then return ga end
            if Panels.isMain(a) ~= Panels.isMain(b) then return Panels.isMain(a) end
            return a.id < b.id
        end)
        for i, p in ipairs(list) do
            if i == 1 then
                p.main = true
            elseif Panels.isMain(p) then
                if p.gen then Panels.disconnectGenerator(p) end
                if p.powered then cutPower(p) end
                p.main = false
            end
        end
    end
    Panels.update()
    transmit()
end

--- Consumo por hora dos aparelhos do predio fora do alcance do proprio gerador.
local function extraConsumption(panel, gen)
    local cell = getCell()
    local gx, gy = gen:getSquare():getX(), gen:getSquare():getY()
    local minZ, maxZ = gen:getMinAffectedLevel(), gen:getMaxAffectedLevel()
    local r2 = KP.generatorRadius() * KP.generatorRadius()
    local total = 0
    -- numa zona, o chao do retangulo e o terreo dos predios se sobrepoem: cada tile conta uma vez
    local counted = {}
    for _, r in ipairs(panel.rects) do
        for y = r.y, r.y + r.h - 1 do
            for x = r.x, r.x + r.w - 1 do
                local dx, dy = x - gx, y - gy
                local coveredByGenerator = dx * dx + dy * dy <= r2 and r.z >= minZ and r.z <= maxZ
                local key = x .. "," .. y .. "," .. r.z
                local sq = not coveredByGenerator and not counted[key] and cell:getGridSquare(x, y, r.z)
                counted[key] = true
                if sq then
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        total = total + objects:get(i):getGeneratorPowerConsumption()
                    end
                end
            end
        end
    end
    return total
end

--- Uma vez por hora de jogo: desconta do tanque o consumo do predio.
--- Se o gerador ficou longe (descarregado), cobra as horas acumuladas quando volta.
function Panels.chargeFuel()
    local now = math.floor(getGameTime():getWorldAgeHours())
    local multiplier = tonumber(SandboxVars.GeneratorFuelConsumption) or 1
    local changed = false
    for _, p in pairs(Panels.all()) do
        local gen = Panels.generatorOf(p)
        if gen then
            local hours = math.min(now - (p.lastHour or now), MAX_CATCHUP_HOURS)
            p.lastHour = now
            local rate = extraConsumption(p, gen)
            if math.abs(rate - (p.rate or 0)) > 0.0001 then
                p.rate = rate
                changed = true
            end
            if hours > 0 and p.powered and gen:isActivated() then
                local fuel = math.max(0, gen:getFuel() - rate * hours * multiplier)
                gen:setFuel(fuel)
                if fuel <= 0 then gen:setActivated(false) end
                gen:sync()
            end
        end
    end
    if changed then transmit() end
    Panels.update()
end

-- ---------------------------------------------------------------------------
-- Mensagens e comandos rapidos (sem acao demorada)
-- ---------------------------------------------------------------------------

--- Mostra uma mensagem (chave de traducao) em cima do jogador.
function Panels.tell(character, key)
    if not key then return end
    if isServer() then
        sendServerCommand(character, Panels.MODULE, "say", { key = key })
    else
        character:Say(getText(key))
    end
end

--- Comandos rapidos: nome -> function(character, panel, args). Os disjuntores
--- (KP_Breakers.lua) acrescentam os deles aqui.
Panels.COMMANDS = {
    rename = function(character, panel, args)
        Panels.rename(panel, args.name)
    end,
    disconnect = function(character, panel, args)
        Panels.disconnectGenerator(panel)
        Panels.tell(character, "IGUI_KnoxPower_GeneratorDisconnected")
    end,
}

--- Executa um comando rapido. Chamado pelo servidor (pedido de cliente) ou
--- direto em single-player.
function Panels.runCommand(character, command, args)
    local fn = Panels.COMMANDS[command]
    local panel = Panels.get(args.id)
    if fn and panel then fn(character, panel, args) end
end

--- Cliente pede um comando rapido (vai pro servidor, ou roda direto em SP).
function Panels.request(character, command, args)
    if isClient() then
        sendClientCommand(character, Panels.MODULE, command, args)
    else
        Panels.runCommand(character, command, args)
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= Panels.MODULE then return end
    if Panels.COMMANDS[command] then Panels.runCommand(player, command, args) end
end

-- ---------------------------------------------------------------------------
-- Eventos
-- ---------------------------------------------------------------------------

--- Quando um chunk carrega, o jogo apaga os pontos dele: reaplica na hora.
local function onLoadChunk(chunk)
    for _, p in pairs(Panels.all()) do
        if p.powered then KP.addPointsToChunk(p.points, chunk) end
    end
end

local lastCheck, lastReconcile = 0, 0
local function onTick()
    local now = getTimestampMs()
    if Panels.isAuthority() and now - lastCheck >= CHECK_MS then
        lastCheck = now
        Panels.update()
    end
    if now - lastReconcile >= RECONCILE_MS then
        lastReconcile = now
        Panels.applyAll()
    end
end

local function onEveryHour()
    if Panels.isAuthority() then Panels.chargeFuel() end
end

local function onInitGlobalModData()
    -- restos do teste da Fase 1 (predio energizado sem gerador) nao valem mais
    if Panels.isAuthority() and ModData.exists("KnoxPower_Phase1") then ModData.remove("KnoxPower_Phase1") end
end

Events.OnClientCommand.Add(onClientCommand)
Events.LoadChunk.Add(onLoadChunk)
Events.OnTick.Add(onTick)
-- No servidor dedicado o OnTick pode nao rodar sem jogadores: reforco por minuto do jogo
Events.EveryOneMinute.Add(function()
    if Panels.isAuthority() then Panels.update() end
    Panels.applyAll()
end)
Events.EveryHours.Add(onEveryHour)
Events.OnInitGlobalModData.Add(onInitGlobalModData)
