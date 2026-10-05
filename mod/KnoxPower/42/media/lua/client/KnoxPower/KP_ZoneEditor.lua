-- Knox Power - editor de zonas no mapa do mundo (Fase 5, so admin).
--
-- No mapa (tecla M), quem pode editar zonas (KP.Zones.canEdit) ve o botao
-- "Knox Power: zonas", que abre um painel com a lista de zonas e as
-- ferramentas. Desenhar = arrastar com o botao esquerdo no mapa (o mapa nao
-- se mexe enquanto a ferramenta esta ativa; botao direito ou Esc cancela).
-- Toda mudanca vai pro servidor (KP.Zones.request) e volta pela ModData.
--
-- O mapa do jogo (ISWorldMap) e envolvido sem ser substituido: cada funcao
-- original continua rodando; o editor so atua com o painel aberto.

require "ISUI/Maps/ISWorldMap"
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "KnoxPower/KP_Zones"

local KP = KnoxPower
local Zones = KP.Zones

KPZoneEditorPanel = ISPanel:derive("KPZoneEditorPanel")

local FONT = UIFont.Small
local PAD = 8
local BTN_H = 22
local PANEL_W = 260

-- Ferramentas: nil (navegar), "new" (nova zona), "add" (+ retangulo), "remove"
local TOOL_HINT = {
    new = "IGUI_KnoxPower_ZoneHintDraw",
    add = "IGUI_KnoxPower_ZoneHintDraw",
    remove = "IGUI_KnoxPower_ZoneHintRemove",
}

-- ---------------------------------------------------------------------------
-- Painel
-- ---------------------------------------------------------------------------

function KPZoneEditorPanel:addButton(y, title, onclick)
    local btn = ISButton:new(PAD, y, PANEL_W - PAD * 2, BTN_H, title, self, onclick)
    btn:initialise()
    btn:instantiate()
    self:addChild(btn)
    return btn
end

function KPZoneEditorPanel:createChildren()
    local th = getTextManager():getFontHeight(FONT)
    local y = PAD + th + PAD
    self.list = ISScrollingListBox:new(PAD, y, PANEL_W - PAD * 2, 140)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = th + 6
    self.list.font = FONT
    self:addChild(self.list)
    y = y + 140 + PAD
    self:addButton(y, getText("IGUI_KnoxPower_ZoneNew"), KPZoneEditorPanel.onNew); y = y + BTN_H + 4
    self.addBtn = self:addButton(y, getText("IGUI_KnoxPower_ZoneAddRect"), KPZoneEditorPanel.onAdd); y = y + BTN_H + 4
    self.removeBtn = self:addButton(y, getText("IGUI_KnoxPower_ZoneRemoveRect"), KPZoneEditorPanel.onRemoveRect); y = y + BTN_H + 4
    self.renameBtn = self:addButton(y, getText("IGUI_KnoxPower_ZoneRename"), KPZoneEditorPanel.onRename); y = y + BTN_H + 4
    self.gotoBtn = self:addButton(y, getText("IGUI_KnoxPower_ZoneGoTo"), KPZoneEditorPanel.onGoTo); y = y + BTN_H + 4
    self.deleteBtn = self:addButton(y, getText("IGUI_KnoxPower_ZoneDelete"), KPZoneEditorPanel.onDelete); y = y + BTN_H + 4
    self:addButton(y, getText("IGUI_KnoxPower_ZoneExport"), KPZoneEditorPanel.onExport); y = y + BTN_H + PAD
    self.hintY = y
    self:setHeight(y + th * 3 + PAD)
end

--- Zona selecionada na lista (ou nil).
function KPZoneEditorPanel:selectedZone()
    local row = self.list.items[self.list.selected]
    return row and Zones.get(row.item) or nil
end

--- Refaz a lista quando as zonas mudam (mantem a selecao pelo id).
function KPZoneEditorPanel:refreshList()
    local ids = {}
    for id in pairs(Zones.all()) do table.insert(ids, tonumber(id)) end
    table.sort(ids)
    local signature = ""
    for _, id in ipairs(ids) do
        local z = Zones.get(id)
        signature = signature .. id .. ":" .. z.name .. ":" .. #z.rects .. ";"
    end
    if signature == self.signature then return end
    self.signature = signature
    local keep = self.list.items[self.list.selected] and self.list.items[self.list.selected].item
    self.list:clear()
    for _, id in ipairs(ids) do
        local z = Zones.get(id)
        self.list:addItem(getText("IGUI_KnoxPower_ZoneListItem", z.name, #z.rects), id)
        if id == keep or (self.selectId and id == self.selectId) then self.list.selected = #self.list.items end
    end
    self.selectId = nil
end

function KPZoneEditorPanel:prerender()
    self:refreshList()
    local hasZone = self:selectedZone() ~= nil
    for _, btn in ipairs({ self.addBtn, self.removeBtn, self.renameBtn, self.gotoBtn, self.deleteBtn }) do
        btn:setEnable(hasZone)
    end
    ISPanel.prerender(self)
end

function KPZoneEditorPanel:render()
    ISPanel.render(self)
    self:drawText(getText("IGUI_KnoxPower_ZoneTitle"), PAD, PAD, 1, 1, 1, 1, FONT)
    local hint = TOOL_HINT[self.map.kpTool] or "IGUI_KnoxPower_ZoneHintIdle"
    local th = getTextManager():getFontHeight(FONT)
    local y = self.hintY
    -- dica com varias linhas separadas por "|" (sem gmatch: o Lua do jogo pode nao ter)
    local text, start = getText(hint), 1
    while start <= #text do
        local stop = string.find(text, "|", start, true) or (#text + 1)
        self:drawText(string.sub(text, start, stop - 1), PAD, y, 0.9, 0.9, 0.6, 1, FONT)
        y = y + th
        start = stop + 1
    end
end

function KPZoneEditorPanel:setTool(tool)
    self.map.kpTool = tool
    self.map.kpDrag = nil
end

function KPZoneEditorPanel:onNew() self:setTool("new") end
function KPZoneEditorPanel:onAdd() self:setTool("add") end
function KPZoneEditorPanel:onRemoveRect() self:setTool("remove") end

function KPZoneEditorPanel:onRename()
    local zone = self:selectedZone()
    if not zone then return end
    local modal = ISTextBox:new(0, 0, 280, 180, getText("IGUI_KnoxPower_ZoneRenamePrompt"), zone.name, self,
        function(target, button)
            if button.internal == "OK" then
                Zones.request(getPlayer(), "rename", { id = zone.id, name = button.parent.entry:getText() })
            end
        end)
    modal:initialise()
    modal:addToUIManager()
end

function KPZoneEditorPanel:onDelete()
    local zone = self:selectedZone()
    if not zone then return end
    local modal = ISModalDialog:new(0, 0, 300, 150, getText("IGUI_KnoxPower_ZoneDeleteConfirm", zone.name), true, self,
        function(target, button)
            if button.internal == "YES" then Zones.request(getPlayer(), "delete", { id = zone.id }) end
        end)
    modal:initialise()
    modal:addToUIManager()
end

function KPZoneEditorPanel:onGoTo()
    local zone = self:selectedZone()
    local r = zone and zone.rects[1]
    if r then self.map.mapAPI:centerOn(r.x + r.w / 2, r.y + r.h / 2) end
end

function KPZoneEditorPanel:onExport()
    local ok = Zones.export()
    getPlayer():Say(getText(ok and "IGUI_KnoxPower_ZoneExported" or "IGUI_KnoxPower_ZoneExportFailed", Zones.EXPORT_FILE))
end

function KPZoneEditorPanel:new(x, y, map)
    local o = ISPanel:new(x, y, PANEL_W, 400)
    setmetatable(o, self)
    self.__index = self
    o.map = map
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.8 }
    return o
end

-- ---------------------------------------------------------------------------
-- Desenho das zonas no mapa
-- ---------------------------------------------------------------------------

local function worldRectToUI(map, x1, y1, x2, y2)
    local api = map.mapAPI
    return {
        api:worldToUIX(x1, y1), api:worldToUIY(x1, y1),
        api:worldToUIX(x2, y1), api:worldToUIY(x2, y1),
        api:worldToUIX(x2, y2), api:worldToUIY(x2, y2),
        api:worldToUIX(x1, y2), api:worldToUIY(x1, y2),
    }
end

--- Contorno de um retangulo do mundo (funciona no mapa de cima e no isometrico).
local function drawWorldRect(map, x1, y1, x2, y2, r, g, b, a, thick)
    local p = worldRectToUI(map, x1, y1, x2, y2)
    local white = Texture:getWhite()
    for i = 0, 3 do
        local j = (i + 1) % 4
        map.javaObject:DrawLine(white, p[i * 2 + 1], p[i * 2 + 2], p[j * 2 + 1], p[j * 2 + 2], thick, r, g, b, a)
    end
end

--- Area (predios incluidos) da zona selecionada, recalculada so quando a zona muda.
local areaCache = { sig = nil, rects = {} }
local function zoneArea(zone)
    local sig = zone.id .. ":"
    for _, r in ipairs(zone.rects) do sig = sig .. r.x .. "," .. r.y .. "," .. r.w .. "," .. r.h .. ";" end
    if areaCache.sig ~= sig then
        areaCache.sig = sig
        areaCache.rects = {}
        local seen = {}
        for _, r in ipairs(Zones.area(zone)) do
            local key = r.x .. "," .. r.y .. "," .. r.w .. "," .. r.h
            -- so os comodos (o chao da zona ja e desenhado), um contorno por planta
            if not r.ground and not seen[key] then
                seen[key] = true
                table.insert(areaCache.rects, r)
            end
        end
    end
    return areaCache.rects
end

--- Predio sob o mouse: contorno dos comodos (mostra onde ele comeca e termina).
local function renderHoverBuilding(map)
    local mx, my = map:getMouseX(), map:getMouseY()
    local wx, wy = math.floor(map.mapAPI:uiToWorldX(mx, my)), math.floor(map.mapAPI:uiToWorldY(mx, my))
    local def = getWorld():getMetaGrid():getBuildingAt(wx, wy)
    if not def then return end
    local seen = {}
    for _, r in ipairs(KP.buildingRects(def)) do
        local key = r.x .. "," .. r.y .. "," .. r.w .. "," .. r.h
        if not seen[key] then
            seen[key] = true
            drawWorldRect(map, r.x, r.y, r.x + r.w, r.y + r.h, 0.3, 0.9, 1, 1, 2)
        end
    end
end

local function renderZones(map)
    local editor = map.kpEditor
    local selected = editor:selectedZone()
    if selected then
        -- predios que recebem energia por essa zona (encostam nos retangulos)
        for _, r in ipairs(zoneArea(selected)) do
            drawWorldRect(map, r.x, r.y, r.x + r.w, r.y + r.h, 0.3, 1, 0.4, 0.6, 1)
        end
    end
    renderHoverBuilding(map)
    for _, zone in pairs(Zones.all()) do
        local isSel = selected and selected.id == zone.id
        for _, r in ipairs(zone.rects) do
            if isSel then
                drawWorldRect(map, r.x, r.y, r.x + r.w, r.y + r.h, 0.2, 1, 0.3, 1, 3)
            else
                drawWorldRect(map, r.x, r.y, r.x + r.w, r.y + r.h, 1, 0.85, 0.1, 0.9, 2)
            end
        end
        local r = zone.rects[1]
        if r then
            local api = map.mapAPI
            map:drawText(zone.name, api:worldToUIX(r.x, r.y) + 4, api:worldToUIY(r.x, r.y) + 2,
                1, 1, isSel and 0.4 or 0.2, 1, FONT)
        end
    end
    local drag = map.kpDrag
    if drag then
        drawWorldRect(map, math.min(drag.x1, drag.x2), math.min(drag.y1, drag.y2),
            math.max(drag.x1, drag.x2) + 1, math.max(drag.y1, drag.y2) + 1, 0.3, 0.9, 1, 1, 2)
    end
end

-- ---------------------------------------------------------------------------
-- Envolve o mapa do jogo
-- ---------------------------------------------------------------------------

local function worldAt(map, x, y)
    return math.floor(map.mapAPI:uiToWorldX(x, y)), math.floor(map.mapAPI:uiToWorldY(x, y))
end

local function toggleEditor(map)
    local editor = map.kpEditor
    local show = not editor:getIsVisible()
    editor:setVisible(show)
    if show then
        -- mapa de cima (retangulos retos) e grade de tiles (pra ver o tamanho certo)
        map.mapAPI:setBoolean("Isometric", false)
        map.kpTileGridBefore = map.mapAPI:getBoolean("TileGrid")
        map.mapAPI:setBoolean("TileGrid", true)
        editor:bringToTop()
    else
        editor:setTool(nil)
        map.mapAPI:setBoolean("TileGrid", map.kpTileGridBefore == true)
    end
end

local original = {
    createChildren = ISWorldMap.createChildren,
    render = ISWorldMap.render,
    onMouseDown = ISWorldMap.onMouseDown,
    onMouseMove = ISWorldMap.onMouseMove,
    onMouseUp = ISWorldMap.onMouseUp,
    onRightMouseDown = ISWorldMap.onRightMouseDown,
    onKeyPress = ISWorldMap.onKeyPress,
}

function ISWorldMap:createChildren()
    original.createChildren(self)
    if not Zones.canEdit(getPlayer()) then return end
    local btn = ISButton:new(10, self.height - 10 - BTN_H - 40, 160, BTN_H, getText("IGUI_KnoxPower_ZoneButton"), self, toggleEditor)
    btn:initialise()
    btn.anchorTop = false
    btn.anchorBottom = true
    self:addChild(btn)
    self.kpButton = btn
    local editor = KPZoneEditorPanel:new(10, 120, self)
    editor:initialise()
    editor:instantiate()
    editor:setVisible(false)
    self:addChild(editor)
    self.kpEditor = editor
end

function ISWorldMap:render()
    original.render(self)
    if self.kpEditor and self.kpEditor:getIsVisible() then renderZones(self) end
end

local function toolActive(map)
    return map.kpEditor and map.kpEditor:getIsVisible() and map.kpTool ~= nil
end

function ISWorldMap:onMouseDown(x, y)
    if not toolActive(self) then return original.onMouseDown(self, x, y) end
    local wx, wy = worldAt(self, x, y)
    if self.kpTool == "remove" then
        -- clicou dentro de um retangulo da zona selecionada: remove ele
        local zone = self.kpEditor:selectedZone()
        for i, r in ipairs(zone and zone.rects or {}) do
            if wx >= r.x and wx < r.x + r.w and wy >= r.y and wy < r.y + r.h then
                Zones.request(getPlayer(), "removeRect", { id = zone.id, index = i })
                break
            end
        end
        return true
    end
    self.kpDrag = { x1 = wx, y1 = wy, x2 = wx, y2 = wy }
    return true
end

function ISWorldMap:onMouseMove(dx, dy)
    if not (toolActive(self) and self.kpDrag) then return original.onMouseMove(self, dx, dy) end
    self.kpDrag.x2, self.kpDrag.y2 = worldAt(self, self:getMouseX(), self:getMouseY())
    return true
end

function ISWorldMap:onMouseUp(x, y)
    if not (toolActive(self) and self.kpDrag) then return original.onMouseUp(self, x, y) end
    local d = self.kpDrag
    self.kpDrag = nil
    d.x2, d.y2 = worldAt(self, x, y)
    local args = { x1 = d.x1, y1 = d.y1, x2 = d.x2, y2 = d.y2 }
    if self.kpTool == "new" then
        Zones.request(getPlayer(), "create", args)
        -- a zona nova aparece selecionada quando a lista atualizar
        self.kpEditor.selectId = Zones.data().nextId
        self.kpTool = "add" -- continua desenhando retangulos na mesma zona
    else
        local zone = self.kpEditor:selectedZone()
        if zone then
            args.id = zone.id
            Zones.request(getPlayer(), "addRect", args)
        end
    end
    return true
end

function ISWorldMap:onRightMouseDown(x, y)
    if toolActive(self) then
        self.kpEditor:setTool(nil)
        return true
    end
    return original.onRightMouseDown(self, x, y)
end

function ISWorldMap:onKeyPress(key)
    if toolActive(self) and key == Keyboard.KEY_ESCAPE then
        self.kpEditor:setTool(nil)
        return true
    end
    if original.onKeyPress then return original.onKeyPress(self, key) end
end
