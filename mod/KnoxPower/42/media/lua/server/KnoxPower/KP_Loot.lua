-- Knox Power - onde as caixas de quadro aparecem no mundo (DESIGN.md, "Obtencao").
--
-- Lojas de construcao/ferragens e fabricas: pouco, mas quase certo (um ou
-- outro por lugar, nao pilhas). Garagens: ~1 em cada 100. O peso e por
-- "rolagem" do container (peso 1 ~ 1% por rolagem; garagem tem 4 rolagens).

require "Items/ProceduralDistributions"

local STORES = {
    "ToolStoreMisc", "ToolStoreTools", "CrateElectronics",
    "WireFactoryElectric", "ToolFactoryTools", "RadioFactoryComponents",
}
local GARAGES = { "GarageTools", "GarageMetalwork" }

local STORE_WEIGHTS = { PowerPanelSmall = 1.5, PowerPanelMedium = 1.0, PowerPanelLarge = 0.5 }
local GARAGE_WEIGHTS = { PowerPanelSmall = 0.15, PowerPanelMedium = 0.07, PowerPanelLarge = 0.03 }

local function add(listNames, weights)
    for _, name in ipairs(listNames) do
        local dist = ProceduralDistributions.list[name]
        if dist and dist.items then
            for item, weight in pairs(weights) do
                table.insert(dist.items, "KnoxPower." .. item)
                table.insert(dist.items, weight)
            end
        else
            print("[Knox Power] tabela de loot nao encontrada: " .. name)
        end
    end
end

add(STORES, STORE_WEIGHTS)
add(GARAGES, GARAGE_WEIGHTS)
