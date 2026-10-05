-- Knox Power - aparelhos que podem ir num disjuntor (Fase 4).
--
-- Cada tipo ("kind") sabe dizer se esta ligado e como desligar/religar do
-- mesmo jeito que as acoes do proprio jogo (que ja sincronizam em servidor):
--   light   -> IsoLightSwitch:setActive        (ISToggleLightAction)
--   radio   -> DeviceData:setIsTurnedOn        (TV e radio; ISRadioAction)
--   stove   -> IsoStove:Toggle                 (ISToggleStoveAction)
--   laundry -> setActivated + sendObjectChange (ISToggleClothingWasher/Dryer)
--   fridge  -> troca de tipo do compartimento  (KP_Fridge.lua)

require "KnoxPower/KP_Fridge"

local KP = KnoxPower
KP.Devices = KP.Devices or {}
local Devices = KP.Devices

local LAUNDRY = { "IsoClothingWasher", "IsoClothingDryer", "IsoCombinationWasherDryer" }

--- Tipo do aparelho, ou nil se nao da pra por num disjuntor.
function Devices.kindOf(obj)
    if not obj then return nil end
    if KP.fridgeState(obj) then return "fridge" end
    if instanceof(obj, "IsoLightSwitch") then return "light" end
    if instanceof(obj, "IsoWaveSignal") then
        local data = obj:getDeviceData()
        -- radio a pilha nao depende da rede eletrica
        if data and not data:getIsBatteryPowered() then return "radio" end
        return nil
    end
    if instanceof(obj, "IsoStove") then return "stove" end
    for _, class in ipairs(LAUNDRY) do
        if instanceof(obj, class) then return "laundry" end
    end
    return nil
end

function Devices.isOn(obj, kind)
    if kind == "fridge" then return KP.fridgeState(obj) == "on" end
    if kind == "light" then return obj:isActivated() end
    if kind == "radio" then return obj:getDeviceData():getIsTurnedOn() end
    if kind == "stove" then return obj:Activated() end
    if kind == "laundry" then return obj:isActivated() end
    return false
end

local function laundryChange(obj)
    if instanceof(obj, "IsoClothingDryer") then return IsoObjectChange.DRYER_STATE end
    if instanceof(obj, "IsoCombinationWasherDryer") and not obj:isModeWasher() then
        return IsoObjectChange.DRYER_STATE
    end
    return IsoObjectChange.WASHER_STATE
end

--- Liga (on=true) ou desliga o aparelho. Chamado so pelo servidor / single-player.
function Devices.setOn(obj, kind, on)
    if Devices.isOn(obj, kind) == on then return end
    if kind == "fridge" then
        KP.setFridgeOn(obj, on)
    elseif kind == "light" then
        obj:setActive(on)
    elseif kind == "radio" then
        obj:getDeviceData():setIsTurnedOn(on)
    elseif kind == "stove" then
        obj:Toggle()
    elseif kind == "laundry" then
        obj:setActivated(on)
        obj:sendObjectChange(laundryChange(obj))
    end
end

--- Acha no mapa o aparelho de um registro {x, y, z, kind, sprite}.
--- Prefere o objeto do mesmo tipo com o mesmo sprite; nil se o tile nao
--- estiver carregado ou o aparelho sumiu. Devolve tambem se o tile carregou.
function Devices.find(device)
    local sq = getCell():getGridSquare(device.x, device.y, device.z)
    if not sq then return nil, false end
    local objects = sq:getObjects()
    local fallback
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if Devices.kindOf(obj) == device.kind then
            local sprite = obj:getSprite()
            if sprite and sprite:getName() == device.sprite then return obj, true end
            fallback = fallback or obj
        end
    end
    return fallback, true
end

--- Registro que identifica o aparelho (guardado no quadro).
function Devices.recordOf(obj)
    local sq = obj:getSquare()
    local sprite = obj:getSprite()
    return {
        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        kind = Devices.kindOf(obj),
        sprite = sprite and sprite:getName() or "",
    }
end

--- Chave do aparelho (tile + tipo): um aparelho de cada tipo por tile.
function Devices.key(d)
    return d.x .. "," .. d.y .. "," .. d.z .. "," .. d.kind
end
