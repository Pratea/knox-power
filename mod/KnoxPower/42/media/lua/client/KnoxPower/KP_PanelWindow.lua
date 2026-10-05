-- Knox Power - janela do quadro (HUD, Fase 4).
--
-- Mostra gerador/combustivel/tempo restante e a lista de disjuntores, com
-- liga/desliga, renomear, remover, adicionar, ligar/desligar todos e a chave
-- geral. So mostra e pede: toda mudanca vai pro servidor (Panels.request) e
-- volta pela lista de quadros (ModData), que a janela relê sozinha.

require "ISUI/ISCollapsableWindow"
require "KnoxPower/KP_Breakers"

local KP = KnoxPower
local Panels = KP.Panels
local Breakers = KP.Breakers
local Devices = KP.Devices

KPPanelWindow = ISCollapsableWindow:derive("KPPanelWindow")

local FONT = UIFont.Small
local PAD = 10
local ROW_H = 26
local BTN_H = 22
local WIDTH = 560
local MAX_DISTANCE = 6
local REFRESH_MS = 500

local GREEN = { r = 0.15, g = 0.45, b = 0.15, a = 1 }
local RED = { r = 0.5, g = 0.12, b = 0.12, a = 1 }

local function lineHeight()
    return getTextManager():getFontHeight(FONT) + 2
end

function Breakers.displayName(panel, index)
    local b = panel.breakers[index]
    if b and b.name and b.name ~= "" then return b.name end
    return getText("IGUI_KnoxPower_BreakerDefaultName", index)
end

function KPPanelWindow:panel()
    return Panels.get(self.panelId)
end

function KPPanelWindow:request(command, args)
    args = args or {}
    args.id = self.panelId
    Panels.request(self.character, command, args)
end

-- ---------------------------------------------------------------------------
-- Montagem
-- ---------------------------------------------------------------------------

function KPPanelWindow:headerHeight()
    return self:titleBarHeight() + PAD + lineHeight() * 4 + PAD
end

function KPPanelWindow:addButton(x, y, w, title, onclick)
    local btn = ISButton:new(x, y, w, BTN_H, title, self, onclick)
    btn:initialise()
    btn:instantiate()
    self:addChild(btn)
    return btn
end

function KPPanelWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local y = self:headerHeight()
    local w = math.floor((WIDTH - PAD * 2 - 4 * 6) / 5)
    local x = PAD
    self.mainBtn = self:addButton(x, y, w, "", KPPanelWindow.onMain); x = x + w + 6
    self:addButton(x, y, w, getText("IGUI_KnoxPower_AllOn"), KPPanelWindow.onAllOn); x = x + w + 6
    self:addButton(x, y, w, getText("IGUI_KnoxPower_AllOff"), KPPanelWindow.onAllOff); x = x + w + 6
    self.addBtn = self:addButton(x, y, w, getText("IGUI_KnoxPower_AddBreaker"), KPPanelWindow.onAdd); x = x + w + 6
    self:addButton(x, y, w, getText("IGUI_KnoxPower_RenamePanel"), KPPanelWindow.onRenamePanel)
    self.rows = {}
    self:rebuildRows()
end

--- Uma linha por disjuntor: [estado] nome ... [renomear] [remover].
function KPPanelWindow:rebuildRows()
    for _, row in ipairs(self.rows) do
        for _, child in ipairs(row.children) do self:removeChild(child) end
    end
    self.rows = {}
    local panel = self:panel()
    local count = panel and #(panel.breakers or {}) or 0
    local y0 = self:headerHeight() + BTN_H + PAD
    for i = 1, count do
        local y = y0 + (i - 1) * ROW_H
        local state = self:addButton(PAD, y, 70, "", KPPanelWindow.onToggle)
        state.internal = i
        local rename = self:addButton(WIDTH - PAD - 160, y, 80, getText("IGUI_KnoxPower_Rename"), KPPanelWindow.onRenameBreaker)
        rename.internal = i
        local remove = self:addButton(WIDTH - PAD - 76, y, 76, getText("IGUI_KnoxPower_Remove"), KPPanelWindow.onRemove)
        remove.internal = i
        table.insert(self.rows, { y = y, state = state, children = { state, rename, remove } })
    end
    self.breakerCount = count
    local footer = lineHeight() * 2 + PAD
    self:setHeight(y0 + math.max(count, 1) * ROW_H + footer)
end

-- ---------------------------------------------------------------------------
-- Atualizacao
-- ---------------------------------------------------------------------------

--- Consumo atual (por hora) dos aparelhos carregados de cada disjuntor.
local function breakerRates(panel)
    local rates = {}
    for _, d in pairs(panel.devices or {}) do
        local obj = Devices.find(d)
        if obj then
            rates[d.breaker] = (rates[d.breaker] or 0) + obj:getGeneratorPowerConsumption()
        end
    end
    return rates
end

function KPPanelWindow:update()
    ISCollapsableWindow.update(self)
    local panel = self:panel()
    if not panel or self.character:DistToSquared(panel.x + 0.5, panel.y + 0.5) > MAX_DISTANCE * MAX_DISTANCE then
        self:close()
        return
    end
    if #(panel.breakers or {}) ~= self.breakerCount then self:rebuildRows() end

    local now = getTimestampMs()
    if now - (self.lastRefresh or 0) >= REFRESH_MS then
        self.lastRefresh = now
        self.counts = Breakers.deviceCounts(panel)
        self.rates = breakerRates(panel)
        -- secundario: o gerador e o do principal da area
        local main = Panels.mainOf(panel)
        self.gen = main and Panels.generatorOf(main)
    end

    self:setTitle(getText("IGUI_KnoxPower_PanelMenu", Panels.displayName(panel)))
    local mainOn = panel.mainOn ~= false
    self.mainBtn:setTitle(getText(mainOn and "IGUI_KnoxPower_MainOn" or "IGUI_KnoxPower_MainOff"))
    self.mainBtn.backgroundColor = mainOn and GREEN or RED
    self.addBtn:setEnable(#(panel.breakers or {}) < Breakers.capacity(panel))
    for i, row in ipairs(self.rows) do
        local b = panel.breakers[i]
        if b then
            row.state:setTitle(getText(b.on and "IGUI_KnoxPower_On" or "IGUI_KnoxPower_Off"))
            row.state.backgroundColor = b.on and GREEN or RED
        end
    end
end

--- Texto do gerador: combustivel e tempo restante estimado.
function KPPanelWindow:generatorLine(panel)
    local gen = self.gen
    panel = Panels.mainOf(panel) or panel
    if not panel.gen then return getText("IGUI_KnoxPower_InfoNoGenerator") end
    if not gen then return getText("IGUI_KnoxPower_InfoGenerator") end
    local multiplier = tonumber(SandboxVars.GeneratorFuelConsumption) or 1
    -- consumo do proprio gerador (o jogo cobra) + o do resto do predio (o mod cobra)
    local perHour = (gen:getTotalPowerUsing() + (panel.rate or 0)) * multiplier
    local fuel = gen:getFuel()
    local percent = math.floor(gen:getFuelPercentage() + 0.5)
    local line = getText("IGUI_KnoxPower_FuelLine", percent .. "%", string.format("%.3f", perHour))
    if gen:isActivated() and perHour > 0 then
        line = line .. "  " .. getText("IGUI_KnoxPower_TimeLeft", string.format("%.1f", fuel / perHour))
    end
    return line
end

function KPPanelWindow:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed then return end
    local panel = self:panel()
    if not panel then return end
    local lh = lineHeight()
    local y = self:titleBarHeight() + PAD
    local count = #(panel.breakers or {})
    self:drawText(getText("IGUI_KnoxPower_InfoSize", getText("IGUI_KnoxPower_Size_" .. panel.size), Breakers.capacity(panel))
        .. "  -  " .. getText("IGUI_KnoxPower_BreakersUsed", count, Breakers.capacity(panel)), PAD, y, 1, 1, 1, 1, FONT)
    y = y + lh
    self:drawText(Panels.roleText(panel), PAD, y, 0.85, 0.85, 1, 1, FONT)
    y = y + lh
    self:drawText(self:generatorLine(panel), PAD, y, 1, 1, 1, 1, FONT)
    y = y + lh
    local powered = panel.powered
    self:drawText(getText(powered and "IGUI_KnoxPower_InfoPowered" or "IGUI_KnoxPower_InfoUnpowered"), PAD, y,
        powered and 0.5 or 1, powered and 1 or 0.5, 0.5, 1, FONT)

    for i, row in ipairs(self.rows) do
        local n = self.counts and self.counts[i] or 0
        local rate = self.rates and self.rates[i] or 0
        local text = Breakers.displayName(panel, i) .. "   " .. getText("IGUI_KnoxPower_BreakerInfo", n, string.format("%.3f", rate))
        self:drawText(text, PAD + 80, row.y + 3, 1, 1, 1, 1, FONT)
    end
    if count == 0 then
        self:drawText(getText("IGUI_KnoxPower_NoBreakers"), PAD, self:headerHeight() + BTN_H + PAD + 3, 0.8, 0.8, 0.8, 1, FONT)
    end
    local fy = self:getHeight() - lh * 2 - PAD / 2
    self:drawText(getText("IGUI_KnoxPower_GeneralCircuit"), PAD, fy, 0.75, 0.75, 0.75, 1, FONT)
    self:drawText(getText("IGUI_KnoxPower_AssignHint"), PAD, fy + lh, 0.75, 0.75, 0.75, 1, FONT)
end

-- ---------------------------------------------------------------------------
-- Botoes
-- ---------------------------------------------------------------------------

function KPPanelWindow:onMain() self:request("toggleMain") end
function KPPanelWindow:onAllOn() self:request("setAllBreakers", { on = true }) end
function KPPanelWindow:onAllOff() self:request("setAllBreakers", { on = false }) end
function KPPanelWindow:onAdd() self:request("addBreaker") end
function KPPanelWindow:onToggle(button) self:request("toggleBreaker", { breaker = button.internal }) end
function KPPanelWindow:onRemove(button) self:request("removeBreaker", { breaker = button.internal }) end

local function askName(window, title, current, onOk)
    local modal = ISTextBox:new(0, 0, 280, 180, title, current or "", window, function(target, button)
        if button.internal == "OK" then onOk(button.parent.entry:getText()) end
    end, window.playerNum)
    modal:initialise()
    modal:addToUIManager()
end

function KPPanelWindow:onRenameBreaker(button)
    local panel = self:panel()
    local index = button.internal
    if not panel or not panel.breakers[index] then return end
    askName(self, getText("IGUI_KnoxPower_BreakerRenamePrompt"), panel.breakers[index].name, function(name)
        self:request("renameBreaker", { breaker = index, name = name })
    end)
end

function KPPanelWindow:onRenamePanel()
    local panel = self:panel()
    if not panel then return end
    askName(self, getText("IGUI_KnoxPower_RenamePrompt"), panel.name, function(name)
        self:request("rename", { name = name })
    end)
end

function KPPanelWindow:close()
    if KPPanelWindow.instance == self then KPPanelWindow.instance = nil end
    self:removeFromUIManager()
end

function KPPanelWindow:new(x, y, character, panelId)
    local o = ISCollapsableWindow:new(x, y, WIDTH, 200)
    setmetatable(o, self)
    self.__index = self
    o.character = character
    o.playerNum = character:getPlayerNum()
    o.panelId = panelId
    o:setResizable(false)
    return o
end

--- Abre a janela do quadro (fecha a anterior, se houver).
function KPPanelWindow.open(character, panelId)
    if KPPanelWindow.instance then KPPanelWindow.instance:close() end
    local x = getCore():getScreenWidth() / 2 - WIDTH / 2
    local y = getCore():getScreenHeight() / 4
    local window = KPPanelWindow:new(x, y, character, panelId)
    window:initialise()
    window:addToUIManager()
    KPPanelWindow.instance = window
end
