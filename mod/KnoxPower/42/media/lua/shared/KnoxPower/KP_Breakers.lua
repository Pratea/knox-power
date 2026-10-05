-- Knox Power - disjuntores (Fase 4).
--
-- Cada quadro tem ate 4/8/12 disjuntores ({name, on}) e uma lista de aparelhos
-- ligados a eles (panel.devices, chave = tile + tipo). Aparelho sem disjuntor
-- fica no circuito "Geral", que segue so a chave geral do quadro.
--
-- Disjuntor desligado (ou chave geral desligada):
--   * o SERVIDOR confere a cada segundo e desliga o aparelho se alguem ligou
--     (ou se ele carregou ligado) -- e a garantia de verdade;
--   * as acoes do jogo de ligar (luz, fogao, lavadora/secadora, TV/radio)
--     sao recusadas antes, com aviso -- so pra resposta ser imediata;
--   * geladeira/freezer: troca de tipo (KP_Fridge.lua), volta sozinha ao religar;
--   * luzes que estavam acesas quando o disjuntor caiu acendem de novo ao religar.

require "KnoxPower/KP_Panels"
require "KnoxPower/KP_Devices"

local KP = KnoxPower
local Panels = KP.Panels
local Devices = KP.Devices
KP.Breakers = KP.Breakers or {}
local Breakers = KP.Breakers

local ENFORCE_MS = 1000

--- Quadros salvos antes da Fase 4 nao tem esses campos.
function Breakers.ensure(panel)
    panel.breakers = panel.breakers or {}
    panel.devices = panel.devices or {}
    if panel.mainOn == nil then panel.mainOn = true end
end

function Breakers.capacity(panel)
    return Panels.SIZES[panel.size].breakers
end

--- O aparelho deve ficar desligado? (disjuntor dele, chave geral do quadro
--- dele ou chave geral do principal da area desligados)
function Breakers.isOff(panel, device)
    if panel.mainOn == false then return true end
    local main = Panels.mainOf(panel)
    if main and main.mainOn == false then return true end
    local b = device.breaker and (panel.breakers or {})[device.breaker]
    return b ~= nil and not b.on
end

--- Quantos aparelhos em cada disjuntor: {[indice] = n}.
function Breakers.deviceCounts(panel)
    local counts = {}
    for _, d in pairs(panel.devices or {}) do
        counts[d.breaker] = (counts[d.breaker] or 0) + 1
    end
    return counts
end

--- Quadros cuja area (predio ou zona) contem o tile, com 1 tile de folga por
--- causa de interruptores e aparelhos encostados na parede. Principal primeiro.
function Breakers.panelsForSquare(x, y, z)
    for _, p in pairs(Panels.all()) do
        for _, r in ipairs(p.rects) do
            if r.z == z and x >= r.x - 1 and x <= r.x + r.w and y >= r.y - 1 and y <= r.y + r.h then
                return Panels.panelsOfArea(p.buildingKey)
            end
        end
    end
    return {}
end

--- Quadro e registro do aparelho, se ele estiver num disjuntor.
function Breakers.deviceOf(obj)
    local kind = Devices.kindOf(obj)
    if not kind then return nil end
    local key = Devices.key(Devices.recordOf(obj))
    for _, p in pairs(Panels.all()) do
        local d = p.devices and p.devices[key]
        if d then return p, d end
    end
    return nil
end

--- O aparelho esta num disjuntor desligado?
function Breakers.isBlocked(obj)
    local panel, device = Breakers.deviceOf(obj)
    return panel ~= nil and Breakers.isOff(panel, device)
end

-- ---------------------------------------------------------------------------
-- Manter os aparelhos no estado certo (so servidor / single-player)
-- ---------------------------------------------------------------------------

--- Desliga o que deve estar desligado e religa geladeiras/luzes que voltaram.
--- So mexe no que esta carregado; o resto e conferido quando carregar.
function Breakers.enforce(panel)
    Breakers.ensure(panel)
    local changed = false
    for key, d in pairs(panel.devices) do
        local obj, loaded = Devices.find(d)
        if loaded and not obj then
            -- aparelho sumiu (levado embora, quebrado...)
            panel.devices[key] = nil
            changed = true
        elseif obj then
            local on = Devices.isOn(obj, d.kind)
            if Breakers.isOff(panel, d) then
                if on then
                    Devices.setOn(obj, d.kind, false)
                    if d.kind == "light" then
                        d.wasOn = true
                        changed = true
                    end
                end
            elseif d.kind == "fridge" then
                if not on then Devices.setOn(obj, d.kind, true) end
            elseif d.wasOn and panel.powered then
                -- luz que caiu junto com o disjuntor acende de novo
                Devices.setOn(obj, d.kind, true)
                d.wasOn = nil
                changed = true
            end
        end
    end
    return changed
end

function Breakers.enforceAll()
    local changed = false
    for _, p in pairs(Panels.all()) do
        if Breakers.enforce(p) then changed = true end
    end
    if changed and isServer() then ModData.transmit(Panels.MODDATA) end
end

--- Tira o aparelho do disjuntor (volta pro Geral). Geladeira desligada religa.
local function release(panel, key)
    local d = panel.devices[key]
    if not d then return end
    panel.devices[key] = nil
    if d.kind == "fridge" then
        local obj = Devices.find(d)
        if obj then Devices.setOn(obj, d.kind, true) end
    end
end

--- Geladeira desligada que carregou: fica desligada so se estiver num
--- disjuntor desligado. Senao (ex.: sobrou do teste da Fase 2), religa.
function KP.fridgeShouldStayOff(obj)
    local panel, device = Breakers.deviceOf(obj)
    return panel ~= nil and Breakers.isOff(panel, device)
end

-- ---------------------------------------------------------------------------
-- Comandos (pedidos pelo HUD e pelo menu; rodam no servidor / single-player)
-- ---------------------------------------------------------------------------

local C = Panels.COMMANDS

--- Depois de mudar disjuntores: confere aparelhos e manda a lista nova.
local function commit(panel)
    -- energia primeiro (chave geral), pra luz que volta ja achar o quadro energizado
    Panels.update()
    -- todos os quadros: a chave geral do principal tambem afeta os secundarios
    Breakers.ensure(panel)
    Breakers.enforceAll()
    if isServer() then ModData.transmit(Panels.MODDATA) end
end

C.addBreaker = function(character, panel)
    Breakers.ensure(panel)
    local n = #panel.breakers
    if n >= Breakers.capacity(panel) then return Panels.tell(character, "IGUI_KnoxPower_PanelFull") end
    -- nome vazio: o cliente mostra "Disjuntor N" no idioma de quem olha
    table.insert(panel.breakers, { name = "", on = true })
    commit(panel)
end

C.renameBreaker = function(character, panel, args)
    Breakers.ensure(panel)
    local b = panel.breakers[tonumber(args.breaker)]
    if b then b.name = tostring(args.name or ""):sub(1, 30) end
    commit(panel)
end

C.removeBreaker = function(character, panel, args)
    Breakers.ensure(panel)
    local index = tonumber(args.breaker)
    if not panel.breakers[index] then return end
    -- aparelhos desse disjuntor voltam pro Geral; os dos seguintes sobem uma posicao
    local keys = {}
    for key, d in pairs(panel.devices) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        local d = panel.devices[key]
        if d.breaker == index then
            release(panel, key)
        elseif d.breaker > index then
            d.breaker = d.breaker - 1
        end
    end
    table.remove(panel.breakers, index)
    commit(panel)
end

C.toggleBreaker = function(character, panel, args)
    Breakers.ensure(panel)
    local b = panel.breakers[tonumber(args.breaker)]
    if b then b.on = not b.on end
    commit(panel)
end

C.setAllBreakers = function(character, panel, args)
    Breakers.ensure(panel)
    for _, b in ipairs(panel.breakers) do b.on = args.on == true end
    commit(panel)
end

C.toggleMain = function(character, panel)
    Breakers.ensure(panel)
    panel.mainOn = not panel.mainOn
    commit(panel)
end

--- Liga o aparelho a um disjuntor (breaker = 0 -> volta pro Geral).
C.assign = function(character, panel, args)
    Breakers.ensure(panel)
    if not Panels.hasRequirements(character) then return end
    args.x, args.y, args.z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    local obj = Devices.find(args)
    local inArea = false
    for _, p in ipairs(Breakers.panelsForSquare(args.x, args.y, args.z)) do
        if p == panel then inArea = true end
    end
    if not obj or not inArea then
        return Panels.tell(character, "IGUI_KnoxPower_DeviceNotFound")
    end
    local record = Devices.recordOf(obj)
    local key = Devices.key(record)
    local index = tonumber(args.breaker) or 0
    -- um aparelho fica em um disjuntor so: sai de qualquer outro quadro da area
    for _, p in ipairs(Panels.panelsOfArea(panel.buildingKey)) do
        if p ~= panel and p.devices and p.devices[key] then
            release(p, key)
        end
    end
    if index == 0 then
        release(panel, key)
        Panels.tell(character, "IGUI_KnoxPower_DeviceToGeneral")
    elseif panel.breakers[index] then
        local old = panel.devices[key]
        record.breaker = index
        record.wasOn = old and old.wasOn or nil
        panel.devices[key] = record
        Panels.tell(character, "IGUI_KnoxPower_DeviceAssigned")
    end
    commit(panel)
end

-- ---------------------------------------------------------------------------
-- Recusar as acoes do jogo de LIGAR aparelho com disjuntor desligado
-- ---------------------------------------------------------------------------

local function refuse(character)
    if character and not isServer() then character:Say(getText("IGUI_KnoxPower_BreakerIsOff")) end
    return false
end

--- Envolve isValid de uma acao: recusa se for pra ligar e o disjuntor estiver desligado.
local function guard(actionClass, method, getObject, isTurningOn)
    if not actionClass or not actionClass[method] then return end
    local original = actionClass[method]
    actionClass[method] = function(self)
        local obj = getObject(self)
        if obj and instanceof(obj, "IsoObject") and isTurningOn(self, obj) and Breakers.isBlocked(obj) then
            return refuse(self.character)
        end
        return original(self)
    end
end

local patched = false
local function patchVanillaActions()
    if patched then return end
    patched = true
    local function object(self) return self.object end
    guard(ISToggleLightAction, "isValid", object, function(_, o) return not o:isActivated() end)
    guard(ISToggleStoveAction, "isValid", object, function(_, o) return not o:Activated() end)
    guard(ISToggleClothingDryer, "isValid", object, function(_, o) return not o:isActivated() end)
    guard(ISToggleClothingWasher, "isValid", object, function(_, o) return not o:isActivated() end)
    guard(ISToggleComboWasherDryer, "isValid", object, function(_, o) return not o:isActivated() end)
    guard(ISRadioAction, "isValidToggleOnOff", function(self) return self.device end,
        function(self) return self.deviceData and not self.deviceData:getIsTurnedOn() end)
end

-- ---------------------------------------------------------------------------
-- Eventos
-- ---------------------------------------------------------------------------

local lastEnforce = 0
local function onTick()
    if not Panels.isAuthority() then return end
    local now = getTimestampMs()
    if now - lastEnforce < ENFORCE_MS then return end
    lastEnforce = now
    Breakers.enforceAll()
end

Events.OnTick.Add(onTick)
Events.EveryOneMinute.Add(function()
    if Panels.isAuthority() then Breakers.enforceAll() end
end)
-- as acoes do jogo ja estao carregadas quando o jogo termina de iniciar
Events.OnGameBoot.Add(patchVanillaActions)
Events.OnServerStarted.Add(patchVanillaActions)
