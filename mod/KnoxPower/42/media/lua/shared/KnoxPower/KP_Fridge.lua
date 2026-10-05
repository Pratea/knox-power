-- Knox Power - geladeira/freezer desligado.
--
-- Como o Build 42 decide se um compartimento gela (ver DESIGN.md, secao 1):
--   * ItemContainer.getTemperature(): se customTemperature ~= 0, usa ele e
--     ignora todo o resto; senao, com energia e isFridge()/isFreezer() -> 0.2
--     (gelado), sem energia -> esquenta ate 1.0 (temperatura ambiente);
--   * isFreezer() olha SO o tipo ("freezer"); isFridge() olha o tipo
--     ("fridge") OU a propriedade IsFridge do sprite -- que quase toda
--     geladeira do jogo tem. Por isso so trocar o tipo NAO basta pra parar
--     de gelar;
--   * congelar comida (Food.isFreezing) exige isFreezer() + energia;
--   * consumo de gerador e o zumbido procuram compartimentos pelo tipo
--     ("fridge"/"freezer").
-- Desligar = trocar o tipo (para consumo, congelamento e zumbido; e salvo
-- com o mundo) + customTemperature = ambiente (para de gelar mesmo com a
-- propriedade IsFridge). O customTemperature NAO e salvo: e reaplicado
-- sempre que o chunk carrega, olhando so o tipo trocado -- nao precisa de
-- lista de geladeiras desligadas.

require "KnoxPower/KP_Power"

local KP = KnoxPower

--- Tipo normal -> tipo "desligado" (e o contrario).
KP.FRIDGE_OFF_TYPE = { fridge = "knoxpower_fridge_off", freezer = "knoxpower_freezer_off" }
KP.FRIDGE_ON_TYPE = {}
for on, off in pairs(KP.FRIDGE_OFF_TYPE) do KP.FRIDGE_ON_TYPE[off] = on end

--- Temperatura ambiente (o valor que getTemperature devolve sem geladeira).
KP.ROOM_TEMPERATURE = 1.0

--- "on" se o objeto tem compartimento de geladeira/freezer ligado, "off" se
--- tem desligado, nil se nao e geladeira.
function KP.fridgeState(obj)
    if not obj or not obj.getContainerCount then return nil end
    for i = 0, obj:getContainerCount() - 1 do
        local t = obj:getContainerByIndex(i):getType()
        if KP.FRIDGE_OFF_TYPE[t] then return "on" end
        if KP.FRIDGE_ON_TYPE[t] then return "off" end
    end
    return nil
end

--- Liga (on=true) ou desliga a geladeira/freezer. Devolve true se mudou algo.
function KP.setFridgeOn(obj, on)
    local changed = false
    for i = 0, obj:getContainerCount() - 1 do
        local c = obj:getContainerByIndex(i)
        local t = c:getType()
        if on and KP.FRIDGE_ON_TYPE[t] then
            c:setType(KP.FRIDGE_ON_TYPE[t])
            c:setCustomTemperature(0)
            changed = true
        elseif not on and KP.FRIDGE_OFF_TYPE[t] then
            c:setType(KP.FRIDGE_OFF_TYPE[t])
            c:setCustomTemperature(KP.ROOM_TEMPERATURE)
            changed = true
        end
    end
    -- liga/desliga o zumbido e reavalia a energia do objeto
    if changed then obj:checkHaveElectricity() end
    return changed
end

--- Geladeira desligada que carregou: o servidor (ou single-player) confere se
--- ela ainda deve ficar desligada (KP.fridgeShouldStayOff, dos disjuntores) e
--- religa se nao; o cliente so reaplica a temperatura.
local function keepOff(obj)
    if isClient() or not KP.fridgeShouldStayOff then return true end
    if KP.fridgeShouldStayOff(obj) then return true end
    KP.setFridgeOn(obj, true)
    return false
end

--- Reaplica a temperatura ambiente nas geladeiras desligadas de um chunk.
local function applyOffTemperatures(chunk)
    local s = KP.CHUNK_SIZE
    for z = chunk:getMinLevel(), chunk:getMaxLevel() do
        for y = 0, s - 1 do
            for x = 0, s - 1 do
                local sq = chunk:getGridSquare(x, y, z)
                if sq then
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        if KP.fridgeState(obj) == "off" and keepOff(obj) then
                            for j = 0, obj:getContainerCount() - 1 do
                                local c = obj:getContainerByIndex(j)
                                if KP.FRIDGE_ON_TYPE[c:getType()] then
                                    c:setCustomTemperature(KP.ROOM_TEMPERATURE)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

Events.LoadChunk.Add(applyOffTemperatures)
