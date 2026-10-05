-- Knox Power - zonas predefinidas (Fase 5).
--
-- Zona = retangulos desenhados no mapa por um admin (KP_ZoneEditor.lua). Um
-- quadro instalado num predio que encosta numa zona alimenta a ZONA INTEIRA:
--   * o chao dos retangulos (andar 0), e
--   * todos os andares de todo predio que encosta nos retangulos.
-- Fora de qualquer zona, o quadro alimenta so o proprio predio.
--
-- As zonas ficam na ModData do mundo ("KnoxPower_Zones"), decididas pelo
-- servidor. As zonas que vem com o mod (KP_DefaultZones.lua) entram uma vez
-- so, na primeira vez que o mundo roda com o mod. "Exportar" grava as zonas
-- do mundo num arquivo (Zomboid/Lua/KnoxPower_zones.lua) no formato do
-- KP_DefaultZones.lua, pra o autor copiar pra dentro do mod.

require "KnoxPower/KP_Power"
require "KnoxPower/KP_DefaultZones"

local KP = KnoxPower
KP.Zones = KP.Zones or {}
local Zones = KP.Zones

Zones.MODDATA = "KnoxPower_Zones"
Zones.MODULE = "KnoxPowerZones"
--- Maior retangulo aceito (lado, em tiles): evita zona gigante por engano.
Zones.MAX_SIDE = 300
Zones.EXPORT_FILE = "KnoxPower_zones.lua"

function Zones.data()
    local data = ModData.getOrCreate(Zones.MODDATA)
    data.zones = data.zones or {}
    data.nextId = data.nextId or 1
    return data
end

function Zones.all()
    return Zones.data().zones
end

function Zones.get(id)
    return id and Zones.all()[tostring(id)] or nil
end

--- Pode editar zonas? Single-player: sempre (o mundo e do jogador).
--- Servidor: quem pode criar zonas sem PvP (mesma permissao do editor do jogo).
function Zones.canEdit(player)
    if not isClient() and not isServer() then return true end
    if getDebug() then return true end
    local role = player and player:getRole()
    return role ~= nil and role:hasCapability(Capability.CanSetupNonPVPZone)
end

local function rectContains(r, x, y)
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

local function rectsIntersect(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

--- Zona que contem o tile ou encosta em algum retangulo do predio.
--- buildingRects pode ser nil (so o tile conta).
function Zones.zoneFor(x, y, buildingRects)
    for _, zone in pairs(Zones.all()) do
        for _, zr in ipairs(zone.rects) do
            if rectContains(zr, x, y) then return zone end
            for _, br in ipairs(buildingRects or {}) do
                if rectsIntersect(zr, br) then return zone end
            end
        end
    end
    return nil
end

--- Chave do predio: canto do primeiro comodo (mesma em qualquer andar).
function Zones.buildingKey(rects)
    local r = rects[1]
    return r.x .. "," .. r.y .. "," .. r.z
end

--- Area alimentada pela zona: chao dos retangulos + todos os andares de todo
--- predio que encosta neles. Varre o mapa (metadados, nao precisa estar carregado).
function Zones.area(zone)
    local out = {}
    local seen = {}
    local metaGrid = getWorld():getMetaGrid()
    for _, zr in ipairs(zone.rects) do
        -- ground: chao da zona (fora de comodo) -- pode ficar sem energia colado em vizinho
        table.insert(out, { x = zr.x, y = zr.y, w = zr.w, h = zr.h, z = 0, ground = true })
        for y = zr.y, zr.y + zr.h - 1 do
            for x = zr.x, zr.x + zr.w - 1 do
                local def = metaGrid:getBuildingAt(x, y)
                if def then
                    local rects = KP.buildingRects(def)
                    if #rects > 0 then
                        local key = Zones.buildingKey(rects)
                        if not seen[key] then
                            seen[key] = true
                            for _, r in ipairs(rects) do table.insert(out, r) end
                        end
                    end
                end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Edicao (so servidor / single-player)
-- ---------------------------------------------------------------------------

local function transmit()
    if isServer() then ModData.transmit(Zones.MODDATA) end
end

--- Chamado depois de qualquer mudanca: os quadros recalculam a area.
local function changed()
    transmit()
    if KP.Panels and KP.Panels.recomputeAreas then KP.Panels.recomputeAreas() end
end

local function normalizeRect(args)
    local x1, y1 = math.floor(tonumber(args.x1) or 0), math.floor(tonumber(args.y1) or 0)
    local x2, y2 = math.floor(tonumber(args.x2) or 0), math.floor(tonumber(args.y2) or 0)
    local x, y = math.min(x1, x2), math.min(y1, y2)
    local w, h = math.abs(x2 - x1) + 1, math.abs(y2 - y1) + 1
    if w > Zones.MAX_SIDE or h > Zones.MAX_SIDE then return nil end
    return { x = x, y = y, w = w, h = h }
end

Zones.COMMANDS = {
    --- Nova zona com um primeiro retangulo.
    create = function(args)
        local rect = normalizeRect(args)
        if not rect then return end
        local data = Zones.data()
        local id = data.nextId
        data.nextId = id + 1
        local name = tostring(args.name or ""):sub(1, 40)
        if name == "" then name = "Zona " .. id end
        data.zones[tostring(id)] = { id = id, name = name, rects = { rect } }
        changed()
    end,
    addRect = function(args)
        local zone = Zones.get(args.id)
        local rect = normalizeRect(args)
        if zone and rect then
            table.insert(zone.rects, rect)
            changed()
        end
    end,
    removeRect = function(args)
        local zone = Zones.get(args.id)
        local index = tonumber(args.index)
        if zone and index and zone.rects[index] then
            table.remove(zone.rects, index)
            if #zone.rects == 0 then Zones.all()[tostring(zone.id)] = nil end
            changed()
        end
    end,
    rename = function(args)
        local zone = Zones.get(args.id)
        if zone then
            zone.name = tostring(args.name or ""):sub(1, 40)
            transmit()
        end
    end,
    delete = function(args)
        if Zones.get(args.id) then
            Zones.all()[tostring(args.id)] = nil
            changed()
        end
    end,
}

--- Executa um comando de edicao (servidor ou single-player), conferindo permissao.
function Zones.run(player, command, args)
    local fn = Zones.COMMANDS[command]
    if fn and Zones.canEdit(player) then fn(args) end
end

--- Cliente pede (vai pro servidor, ou roda direto em single-player).
function Zones.request(player, command, args)
    if isClient() then
        sendClientCommand(player, Zones.MODULE, command, args)
    else
        Zones.run(player, command, args)
    end
end

--- Grava as zonas atuais no formato do KP_DefaultZones.lua (no PC de quem pediu).
function Zones.export()
    local writer = getFileWriter(Zones.EXPORT_FILE, true, false)
    if not writer then return false end
    writer:write("-- Zonas exportadas pelo editor do Knox Power. Copie a tabela pra\n")
    writer:write("-- media/lua/shared/KnoxPower/KP_DefaultZones.lua pra virem com o mod.\n")
    writer:write("KnoxPower.DEFAULT_ZONES = {\n")
    local ids = {}
    for id in pairs(Zones.all()) do table.insert(ids, tonumber(id)) end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local zone = Zones.get(id)
        local name = tostring(zone.name):gsub("\\", "\\\\"):gsub("\"", "\\\"")
        writer:write("    { name = \"" .. name .. "\", rects = {\n")
        for _, r in ipairs(zone.rects) do
            writer:write(string.format("        { x = %d, y = %d, w = %d, h = %d },\n", r.x, r.y, r.w, r.h))
        end
        writer:write("    } },\n")
    end
    writer:write("}\n")
    writer:close()
    return true
end

-- ---------------------------------------------------------------------------
-- Eventos
-- ---------------------------------------------------------------------------

--- Primeira vez do mundo com o mod: entram as zonas que vem com ele.
local function onInitGlobalModData()
    if isClient() then return end
    local data = Zones.data()
    if data.defaultsLoaded then return end
    data.defaultsLoaded = true
    for _, z in ipairs(KP.DEFAULT_ZONES or {}) do
        local id = data.nextId
        data.nextId = id + 1
        local rects = {}
        for _, r in ipairs(z.rects) do table.insert(rects, { x = r.x, y = r.y, w = r.w, h = r.h }) end
        data.zones[tostring(id)] = { id = id, name = z.name, rects = rects }
    end
end

local function onClientCommand(module, command, player, args)
    if module == Zones.MODULE then Zones.run(player, command, args) end
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.OnClientCommand.Add(onClientCommand)
