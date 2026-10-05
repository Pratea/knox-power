-- Knox Power - acoes demoradas dos quadros (instalar, desinstalar, conectar gerador).
--
-- Padrao do B42: a acao roda no cliente e o complete() roda no SERVIDOR (ou
-- direto em single-player). O servidor recria a acao chamando new() com os
-- campos de MESMO NOME dos parametros do construtor -- por isso cada new()
-- guarda os parametros com o mesmo nome (character, item, square, ...).

require "TimedActions/ISBaseTimedAction"
require "KnoxPower/KP_Panels"

local Panels = KnoxPower.Panels

local function lootAnim(action, low)
    action:setActionAnim("Loot")
    action.character:SetVariable("LootPosition", low and "Low" or "Mid")
    action.character:reportEvent("EventLootItem")
end

local function duration(character, base)
    if character:isTimedActionInstant() then return 1 end
    return base - character:getPerkLevel(Perks.Electricity) * 5
end

-- ---------------------------------------------------------------------------
-- Instalar
-- ---------------------------------------------------------------------------

KPInstallPanelAction = ISBaseTimedAction:derive("KPInstallPanelAction")

function KPInstallPanelAction:isValid()
    return Panels.hasRequirements(self.character)
        and self.character:getInventory():containsRecursive(self.item)
end

function KPInstallPanelAction:waitToStart()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    return self.character:shouldBeTurning()
end

function KPInstallPanelAction:start()
    lootAnim(self, false)
end

function KPInstallPanelAction:perform()
    ISBaseTimedAction.perform(self)
end

function KPInstallPanelAction:complete()
    local err = Panels.install(self.character, self.item, self.square, self.dir)
    if err then
        Panels.tell(self.character, err)
    else
        addXp(self.character, Perks.Electricity, 5)
        Panels.tell(self.character, "IGUI_KnoxPower_Installed")
    end
    return true
end

function KPInstallPanelAction:getDuration()
    return duration(self.character, 300)
end

function KPInstallPanelAction:new(character, item, square, dir)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.square = square
    o.dir = dir
    o.maxTime = o:getDuration()
    return o
end

-- ---------------------------------------------------------------------------
-- Desinstalar
-- ---------------------------------------------------------------------------

KPUninstallPanelAction = ISBaseTimedAction:derive("KPUninstallPanelAction")

function KPUninstallPanelAction:isValid()
    return Panels.hasRequirements(self.character) and self.panelObject:getObjectIndex() ~= -1
end

function KPUninstallPanelAction:waitToStart()
    self.character:faceThisObject(self.panelObject)
    return self.character:shouldBeTurning()
end

function KPUninstallPanelAction:start()
    lootAnim(self, false)
end

function KPUninstallPanelAction:perform()
    ISBaseTimedAction.perform(self)
end

function KPUninstallPanelAction:complete()
    local panel = Panels.get(Panels.idOfObject(self.panelObject))
    if panel then
        Panels.uninstall(self.character, panel)
        Panels.tell(self.character, "IGUI_KnoxPower_Uninstalled")
    end
    return true
end

function KPUninstallPanelAction:getDuration()
    return duration(self.character, 200)
end

function KPUninstallPanelAction:new(character, panelObject)
    local o = ISBaseTimedAction.new(self, character)
    o.panelObject = panelObject
    o.maxTime = o:getDuration()
    return o
end

-- ---------------------------------------------------------------------------
-- Conectar gerador
-- ---------------------------------------------------------------------------

KPConnectGeneratorAction = ISBaseTimedAction:derive("KPConnectGeneratorAction")

function KPConnectGeneratorAction:isValid()
    return Panels.hasRequirements(self.character)
        and self.character:getInventory():containsTypeRecurse("Base.ElectricWire")
        and self.generator:getObjectIndex() ~= -1
end

function KPConnectGeneratorAction:waitToStart()
    self.character:faceThisObject(self.generator)
    return self.character:shouldBeTurning()
end

function KPConnectGeneratorAction:update()
    self.character:faceThisObject(self.generator)
end

function KPConnectGeneratorAction:start()
    lootAnim(self, true)
end

function KPConnectGeneratorAction:perform()
    ISBaseTimedAction.perform(self)
end

function KPConnectGeneratorAction:complete()
    local panel = Panels.get(self.panelId)
    local err = panel and Panels.connectGenerator(self.character, panel, self.generator) or "IGUI_KnoxPower_CantConnect"
    if err then
        Panels.tell(self.character, err)
    else
        addXp(self.character, Perks.Electricity, 5)
        Panels.tell(self.character, "IGUI_KnoxPower_GeneratorConnected")
    end
    return true
end

function KPConnectGeneratorAction:getDuration()
    return duration(self.character, 250)
end

function KPConnectGeneratorAction:new(character, generator, panelId)
    local o = ISBaseTimedAction.new(self, character)
    o.generator = generator
    o.panelId = panelId
    o.maxTime = o:getDuration()
    return o
end
