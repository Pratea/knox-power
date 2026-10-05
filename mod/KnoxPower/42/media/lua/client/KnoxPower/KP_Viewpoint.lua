-- Knox Power - modelo 3D do quadro em 1a pessoa (Viewpoint).
--
-- Registra o pacote de modelos do mod pela API publica do Viewpoint
-- (Viewpoint.ModelPacks.register), o mesmo caminho que o Voxel Studio usa.
-- O manifesto liga os sprites do quadro (knoxpower_01_0..3) aos modelos
-- gerados por tools/build_art.py. Sem o Viewpoint, nao faz nada.

local MANIFEST = "media/voxel-studio/knoxpower.properties"
local registered = false

local function register()
    if registered or not Viewpoint or not Viewpoint.ModelPacks then return end
    local ok, res = pcall(Viewpoint.ModelPacks.register, "KnoxPower", MANIFEST)
    if ok and res then
        registered = true
    elseif not ok then
        print("[Knox Power] Viewpoint: " .. tostring(res))
    end
end

Events.OnGameBoot.Add(register)
Events.OnGameStart.Add(register)
register()
