-- Knox Power - menus do botao direito (cliente).
--
--   * parede de predio, com a caixa do quadro no inventario: instalar;
--   * quadro instalado: abrir (janela dos disjuntores), informacoes, renomear,
--     desconectar gerador, desinstalar;
--   * gerador: conectar ao quadro / desconectar;
--   * aparelho dentro de um predio com quadro: ligar a um disjuntor.
-- Toda decisao vai pro servidor (acoes em shared/TimedActions/KPPanelActions.lua,
-- comandos rapidos em KP_Panels.lua/KP_Breakers.lua). Aqui tambem chega a
-- lista de quadros (ModData) e as mensagens do servidor.

require "KnoxPower/KP_Panels"
require "KnoxPower/KP_Breakers"
require "KnoxPower/KP_PanelWindow"
require "TimedActions/KPPanelActions"

local KP = KnoxPower
local Panels = KP.Panels
local Breakers = KP.Breakers
local Devices = KP.Devices

local function sizeName(size)
    return getText("IGUI_KnoxPower_Size_" .. size)
end

function Panels.displayName(panel)
    if panel.name and panel.name ~= "" then return panel.name end
    return getText("IGUI_KnoxPower_PanelDefaultName", sizeName(panel.size))
end

--- "Principal (zona X)" / "Secundario - energia de Y".
function Panels.roleText(panel)
    local key = panel.buildingKey or ""
    local zone = key:sub(1, 5) == "zone:" and KP.Zones.get(key:sub(6)) or nil
    local where = zone and getText("IGUI_KnoxPower_InZone", zone.name) or getText("IGUI_KnoxPower_InBuilding")
    if Panels.isMain(panel) then
        return getText("IGUI_KnoxPower_RoleMain") .. " - " .. where
    end
    local main = Panels.mainOf(panel)
    return getText("IGUI_KnoxPower_RoleSecondary", main and Panels.displayName(main) or "?") .. " - " .. where
end

--- Deixa a opcao cinza com uma explicacao.
local function disable(option, text)
    option.notAvailable = true
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = text
    option.toolTip = tooltip
end

--- Motivo de nao poder mexer (falta Eletricidade 3 ou chave de fenda), ou nil.
local function missingRequirement(player)
    if not Panels.hasSkill(player) then
        return getText("IGUI_KnoxPower_NeedSkill", Panels.MIN_ELECTRICITY)
    end
    if not Panels.hasScrewdriver(player) then return getText("IGUI_KnoxPower_NeedScrewdriver") end
    return nil
end

-- ---------------------------------------------------------------------------
-- Instalar
-- ---------------------------------------------------------------------------

--- Uma caixa de cada tamanho que o jogador carrega: {size = item}, e quantos
--- tamanhos achou (o Lua do jogo nao tem next() pra checar tabela vazia).
local function panelItems(player)
    local found, count = {}, 0
    local items = player:getInventory():getAllEvalRecurse(function(item)
        return Panels.sizeOfItem(item:getFullType()) ~= nil
    end)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local size = Panels.sizeOfItem(item:getFullType())
        if not found[size] then
            found[size] = item
            count = count + 1
        end
    end
    return found, count
end

local function doInstall(player, item, sq, dir)
    if luautils.walkAdj(player, sq, true) then
        ISTimedActionQueue.add(KPInstallPanelAction:new(player, item, sq, dir))
    end
end

local function addInstallMenu(context, player, sq)
    local items, count = panelItems(player)
    if count == 0 then return end
    -- paredes deste tile que pertencem a um predio (por dentro ou por fora)
    local dirs = {}
    for _, dir in ipairs(Panels.wallsOf(sq)) do
        if Panels.buildingOfWall(sq, dir) then table.insert(dirs, dir) end
    end
    if #dirs == 0 then return end

    local option = context:addOption(getText("IGUI_KnoxPower_Install"))
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(option, sub)
    local missing = missingRequirement(player)
    for _, size in ipairs(Panels.SIZE_ORDER) do
        local item = items[size]
        if item then
            for _, dir in ipairs(dirs) do
                local label = sizeName(size)
                if #dirs > 1 then label = label .. " - " .. getText("IGUI_KnoxPower_Wall_" .. dir) end
                local opt = sub:addOption(label, player, doInstall, item, sq, dir)
                if missing then disable(opt, missing) end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Quadro instalado
-- ---------------------------------------------------------------------------

local function onRenameClick(panel, button)
    if button.internal ~= "OK" then return end
    Panels.request(getPlayer(), "rename", { id = panel.id, name = button.parent.entry:getText() })
end

local function doRename(player, panel)
    local modal = ISTextBox:new(0, 0, 280, 180, getText("IGUI_KnoxPower_RenamePrompt"),
        panel.name or "", panel, onRenameClick, player:getPlayerNum())
    modal:initialise()
    modal:addToUIManager()
end

local function doUninstall(player, obj)
    if luautils.walkAdj(player, obj:getSquare(), true) then
        ISTimedActionQueue.add(KPUninstallPanelAction:new(player, obj))
    end
end

local function addPanelMenu(context, player, obj, panel)
    local option = context:addOption(getText("IGUI_KnoxPower_PanelMenu", Panels.displayName(panel)))
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(option, sub)

    sub:addOption(getText("IGUI_KnoxPower_Open"), player, function()
        if luautils.walkAdj(player, obj:getSquare(), true) then
            KPPanelWindow.open(player, panel.id)
        end
    end)

    -- informacoes (so leitura)
    local info = {
        getText("IGUI_KnoxPower_InfoSize", sizeName(panel.size), Panels.SIZES[panel.size].breakers),
        Panels.roleText(panel),
    }
    if Panels.isMain(panel) then
        table.insert(info, getText(panel.gen and "IGUI_KnoxPower_InfoGenerator" or "IGUI_KnoxPower_InfoNoGenerator"))
    end
    table.insert(info, getText(panel.powered and "IGUI_KnoxPower_InfoPowered" or "IGUI_KnoxPower_InfoUnpowered"))
    if panel.gen then
        table.insert(info, getText("IGUI_KnoxPower_InfoRate", string.format("%.3f", panel.rate or 0)))
    end
    for _, line in ipairs(info) do
        sub:addOption(line).notAvailable = true
    end

    sub:addOption(getText("IGUI_KnoxPower_Rename"), player, doRename, panel)
    if panel.gen then
        sub:addOption(getText("IGUI_KnoxPower_Disconnect"), player, function()
            Panels.request(player, "disconnect", { id = panel.id })
        end)
    end
    local opt = sub:addOption(getText("IGUI_KnoxPower_Uninstall"), player, doUninstall, obj)
    local missing = missingRequirement(player)
    if missing then disable(opt, missing) end
end

-- ---------------------------------------------------------------------------
-- Gerador
-- ---------------------------------------------------------------------------

local function doConnect(player, generator, panelId)
    if luautils.walkAdj(player, generator:getSquare(), true) then
        ISTimedActionQueue.add(KPConnectGeneratorAction:new(player, generator, panelId))
    end
end

local function addGeneratorMenu(context, player, generator)
    local sq = generator:getSquare()
    local gx, gy, gz = sq:getX(), sq:getY(), sq:getZ()
    local connected = Panels.panelOfGenerator(gx, gy, gz)
    if connected then
        context:addOption(getText("IGUI_KnoxPower_DisconnectFrom", Panels.displayName(connected)), player, function()
            Panels.request(player, "disconnect", { id = connected.id })
        end)
        return
    end

    local option = context:addOption(getText("IGUI_KnoxPower_Connect"))
    local near = {}
    for _, p in pairs(Panels.all()) do
        if Panels.isMain(p) and not p.gen and Panels.distanceToBuilding(p, gx, gy) <= Panels.MAX_GENERATOR_DISTANCE then
            table.insert(near, p)
        end
    end
    if #near == 0 then
        return disable(option, getText("IGUI_KnoxPower_NoPanelNear", Panels.MAX_GENERATOR_DISTANCE))
    end
    local missing = missingRequirement(player)
    if not missing and not player:getInventory():containsTypeRecurse("Base.ElectricWire") then
        missing = getText("IGUI_KnoxPower_NeedWire")
    end
    if missing then return disable(option, missing) end

    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(option, sub)
    for _, p in ipairs(near) do
        sub:addOption(Panels.displayName(p), player, doConnect, generator, p.id)
    end
end

-- ---------------------------------------------------------------------------
-- Aparelho -> disjuntor
-- ---------------------------------------------------------------------------

local function doAssign(player, obj, panelId, breaker)
    local args = Devices.recordOf(obj)
    args.id = panelId
    args.breaker = breaker
    if luautils.walkAdj(player, obj:getSquare(), true) then
        Panels.request(player, "assign", args)
    end
end

local function addDeviceMenu(context, player, obj)
    local sq = obj:getSquare()
    local panels = Breakers.panelsForSquare(sq:getX(), sq:getY(), sq:getZ())
    if #panels == 0 then return end
    local currentPanel, current = Breakers.deviceOf(obj)
    local total = 0
    for _, p in ipairs(panels) do total = total + #(p.breakers or {}) end
    local title = getText("IGUI_KnoxPower_AssignMenu", getText("IGUI_KnoxPower_Kind_" .. Devices.kindOf(obj)))
    local option = context:addOption(title)
    local missing = missingRequirement(player)
    if missing then return disable(option, missing) end
    if total == 0 then return disable(option, getText("IGUI_KnoxPower_NoBreakers")) end

    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(option, sub)
    local function mark(label, selected)
        return selected and ("> " .. label) or label
    end
    -- "Geral" tira o aparelho do disjuntor (de qualquer quadro da area)
    local generalPanel = currentPanel or panels[1]
    sub:addOption(mark(getText("IGUI_KnoxPower_General"), not current), player, doAssign, obj, generalPanel.id, 0)
    for _, p in ipairs(panels) do
        local breakers = p.breakers or {}
        for i = 1, #breakers do
            local label = Breakers.displayName(p, i)
            -- com mais de um quadro na area, diz de qual quadro e o disjuntor
            if #panels > 1 then label = Panels.displayName(p) .. ": " .. label end
            local selected = current and currentPanel == p and current.breaker == i
            sub:addOption(mark(label, selected), player, doAssign, obj, p.id, i)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Montagem do menu
-- ---------------------------------------------------------------------------

local function onFillContext(playerNum, context, worldObjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local seen = {}
    local generator
    local devices, seenDevice = {}, {}
    for _, obj in ipairs(worldObjects) do
        local id = Panels.idOfObject(obj)
        local panel = Panels.get(id)
        if panel and not seen[id] then
            seen[id] = true
            addPanelMenu(context, player, obj, panel)
        end
        if not generator and instanceof(obj, "IsoGenerator") then generator = obj end
        if Devices.kindOf(obj) and not seenDevice[obj] then
            seenDevice[obj] = true
            table.insert(devices, obj)
        end
    end
    if generator then addGeneratorMenu(context, player, generator) end
    for _, obj in ipairs(devices) do addDeviceMenu(context, player, obj) end

    local first = worldObjects[1]
    local sq = first and first:getSquare()
    if sq then addInstallMenu(context, player, sq) end
end

-- ---------------------------------------------------------------------------
-- Mensagens do servidor
-- ---------------------------------------------------------------------------

local function onServerCommand(module, command, args)
    if module ~= Panels.MODULE then return end
    if command == "say" then
        local p = getPlayer()
        if p and args.key then p:Say(getText(args.key)) end
    end
end

local function onReceiveGlobalModData(key, data)
    if type(data) ~= "table" then return end
    if key == Panels.MODDATA then
        Panels.onListReceived(data)
    elseif key == KP.Zones.MODDATA then
        ModData.add(KP.Zones.MODDATA, data)
    end
end

-- Geladeira desligada usa o mesmo icone de compartimento da ligada
require "Definitions/ContainerButtonIcons"
for on, off in pairs(KP.FRIDGE_OFF_TYPE) do
    ContainerButtonIcons[off] = ContainerButtonIcons[off] or ContainerButtonIcons[on]
end

Events.OnFillWorldObjectContextMenu.Add(onFillContext)
Events.OnServerCommand.Add(onServerCommand)
Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)
-- Ao entrar num servidor, pede a lista atual de quadros e de zonas
Events.OnGameStart.Add(function()
    if isClient() then
        ModData.request(Panels.MODDATA)
        ModData.request(KP.Zones.MODDATA)
    end
end)
