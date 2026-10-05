-- Knox Power - nucleo: "pontos de energia" que levam energia a uma area.
--
-- Como o Build 42 decide se um tile tem energia (ver DESIGN.md, secao 1):
--   IsoGridSquare:haveElectricity() -> IsoChunk:isGeneratorPoweringSquare(x,y,z)
--   -> o tile esta a no maximo R tiles (circulo, R = GeneratorTileRange) de
--   alguma "posicao de gerador" registrada naquele pedaco do mapa (chunk,
--   8x8 tiles), e dentro do alcance vertical.
-- Este arquivo registra posicoes extras (pontos) com chunk:addGeneratorPos,
-- espalhadas pra cobrir a area inteira. addGeneratorPos ignora repetidas,
-- entao reaplicar e seguro.
--
-- O jogo apaga posicoes sem gerador de verdade quando um chunk carrega
-- (IsoGenerator.chunkLoaded -> IsoChunk:checkForMissingGenerators): por isso
-- os pontos sao reaplicados no evento LoadChunk e periodicamente.

KnoxPower = KnoxPower or {}
local KP = KnoxPower

KP.CHUNK_SIZE = 8 -- IsoChunk.CHUNK_SIZE_IN_SQUARES

--- Raio de alcance de um gerador (opcao de sandbox "Alcance do gerador").
function KP.generatorRadius()
    local r = SandboxVars and tonumber(SandboxVars.GeneratorTileRange)
    if not r or r < 1 then r = 20 end
    return r
end

-- ---------------------------------------------------------------------------
-- Area de um predio
-- ---------------------------------------------------------------------------

--- Retangulos dos comodos de um predio: lista de {x, y, w, h, z}.
function KP.buildingRects(def)
    local out = {}
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        local z = room:getZ()
        local rects = room:getRects()
        for j = 0, rects:size() - 1 do
            local r = rects:get(j)
            table.insert(out, { x = r:getX(), y = r:getY(), w = r:getW(), h = r:getH(), z = z })
        end
    end
    return out
end

--- Alcance vertical de um gerador (opcao de sandbox), em andares.
function KP.verticalRange()
    local v = SandboxVars and tonumber(SandboxVars.GeneratorVerticalPowerRange)
    if not v or v < 0 then v = 3 end
    return v
end

local function rectHas(r, x, y)
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

--- Tiles a proteger num chunk ({x, y}): os comodos de OUTROS predios em
--- andares que um ponto no andar z alcanca, mais 1 tile em volta deles (luz de
--- varanda, ar-condicionado etc. ficam presos na parede, no tile de fora) --
--- menos os tiles que sao comodo da propria area (isMust).
local function victimsInChunk(cx, cy, z, vr, isAreaRect, isMust, rectsCache)
    local s = KP.CHUNK_SIZE
    local metaGrid = getWorld():getMetaGrid()
    local defs, seen = {}, {}
    -- 1 tile alem do chunk: o anel de um vizinho do chunk ao lado entra neste
    for y = cy * s - 1, cy * s + s do
        for x = cx * s - 1, cx * s + s do
            local def = metaGrid:getBuildingAt(x, y)
            if def and not seen[def] then
                seen[def] = true
                table.insert(defs, def)
            end
        end
    end
    local tiles, has = {}, {}
    for _, def in ipairs(defs) do
        local rects = rectsCache[def]
        if not rects then
            rects = KP.buildingRects(def)
            rectsCache[def] = rects
        end
        for _, r in ipairs(rects) do
            if math.abs(r.z - z) <= vr and not isAreaRect(r) then
                for y = math.max(r.y - 1, cy * s), math.min(r.y + r.h, cy * s + s - 1) do
                    for x = math.max(r.x - 1, cx * s), math.min(r.x + r.w, cx * s + s - 1) do
                        local key = x .. "," .. y
                        local inRoom = x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
                        if not has[key] and (inRoom or not isMust(x, y, r.z)) then
                            has[key] = true
                            table.insert(tiles, { x = x, y = y })
                        end
                    end
                end
            end
        end
    end
    return tiles
end

--- Escolhe pontos (no andar z) que cobrem os tiles `targets` sem alcancar
--- nenhum tile de `victims` (alcance = isPoweringSquare do jogo: dx²+dy² <= R²).
--- Busca gulosa numa grade de candidatos em volta do chunk. Se algum tile nao
--- da pra cobrir sem vazar (vizinho colado), aceita o ponto que menos vaza.
local function pickPoints(cx, cy, z, radius, targets, victims)
    local s = KP.CHUNK_SIZE
    local r2 = radius * radius
    local x0, y0 = cx * s - radius, cy * s - radius
    local x1, y1 = cx * s + s - 1 + radius, cy * s + s - 1 + radius
    local remaining = targets
    local chosen = {}
    for _, step in ipairs({ 2, 1 }) do
        local candidates = {}
        for py = y0, y1, step do
            for px = x0, x1, step do
                local safe = true
                for _, v in ipairs(victims) do
                    local dx, dy = v.x - px, v.y - py
                    if dx * dx + dy * dy <= r2 then
                        safe = false
                        break
                    end
                end
                if safe then table.insert(candidates, { x = px, y = py }) end
            end
        end
        while #remaining > 0 do
            local best, bestCount = nil, 0
            for _, c in ipairs(candidates) do
                local count = 0
                for _, t in ipairs(remaining) do
                    local dx, dy = t.x - c.x, t.y - c.y
                    if dx * dx + dy * dy <= r2 then count = count + 1 end
                end
                if count > bestCount then best, bestCount = c, count end
            end
            if not best then break end
            table.insert(chosen, best)
            local left = {}
            for _, t in ipairs(remaining) do
                local dx, dy = t.x - best.x, t.y - best.y
                if dx * dx + dy * dy > r2 then table.insert(left, t) end
            end
            remaining = left
        end
        if #remaining == 0 then break end
    end
    -- sobrou tile cercado de vizinho (impossivel sem vazar). Chao de zona
    -- (fora de comodo) fica sem energia; tile de comodo da area aceita o ponto
    -- que menos vaza por tile coberto.
    local must = {}
    for _, t in ipairs(remaining) do
        if t.must then table.insert(must, t) end
    end
    remaining = must
    while #remaining > 0 do
        local best, bestScore, bestCovered = nil, math.huge, nil
        for py = y0, y1 do
            for px = x0, x1 do
                local covered = 0
                for _, t in ipairs(remaining) do
                    local dx, dy = t.x - px, t.y - py
                    if dx * dx + dy * dy <= r2 then covered = covered + 1 end
                end
                if covered > 0 then
                    local hits = 0
                    for _, v in ipairs(victims) do
                        local dx, dy = v.x - px, v.y - py
                        if dx * dx + dy * dy <= r2 then hits = hits + 1 end
                    end
                    local score = hits / covered
                    if score < bestScore then best, bestScore = { x = px, y = py }, score end
                end
            end
        end
        if not best then break end
        table.insert(chosen, best)
        local left = {}
        for _, t in ipairs(remaining) do
            local dx, dy = t.x - best.x, t.y - best.y
            if dx * dx + dy * dy > r2 then table.insert(left, t) end
        end
        remaining = left
    end
    return chosen
end

--- Pontos que cobrem todos os retangulos, andar por andar, cada um preso a UM
--- chunk (p.cx, p.cy). O jogo so procura posicoes de gerador na lista do chunk
--- do proprio tile (IsoChunk.isGeneratorPoweringSquare), entao um ponto
--- registrado so no chunk dele nao energiza nada fora desse chunk:
--- chunk so com a area (ou com area + rua) -> 1 ponto no meio, cobre tudo;
--- chunk com comodo de OUTRO predio -> pontos escolhidos pra nao alcancar esse
--- comodo (pickPoints). Assim a energia para na area, nao vaza pros vizinhos.
function KP.coverPoints(rects, radius)
    local s = KP.CHUNK_SIZE
    local vr = KP.verticalRange()
    local sig = {}
    for _, r in ipairs(rects) do sig[r.x .. "," .. r.y .. "," .. r.w .. "," .. r.h .. "," .. r.z] = true end
    local function isAreaRect(r)
        return sig[r.x .. "," .. r.y .. "," .. r.w .. "," .. r.h .. "," .. r.z] == true
    end
    local byZ, levels = {}, {}
    --- tile dentro de comodo da area (retangulo que nao e so chao de zona)
    local function isMust(x, y, z)
        for _, r in ipairs(byZ[z] or {}) do
            if not r.ground and rectHas(r, x, y) then return true end
        end
        return false
    end
    for _, r in ipairs(rects) do
        if not byZ[r.z] then
            byZ[r.z] = {}
            table.insert(levels, r.z)
        end
        table.insert(byZ[r.z], r)
    end
    table.sort(levels)
    local points = {}
    local rectsCache = {}
    -- chunk inteiro ja coberto num andar (ponto no meio, sem vizinho): o mesmo
    -- ponto alcanca os andares ate vr acima/abaixo, nao precisa de outro
    local fullUpTo = {}
    for _, z in ipairs(levels) do
        local list = byZ[z]
        -- chunks com algum tile da area neste andar
        local chunks, order = {}, {}
        for _, r in ipairs(list) do
            for cy = math.floor(r.y / s), math.floor((r.y + r.h - 1) / s) do
                for cx = math.floor(r.x / s), math.floor((r.x + r.w - 1) / s) do
                    local key = cx .. "," .. cy
                    if not chunks[key] then
                        chunks[key] = { cx = cx, cy = cy }
                        table.insert(order, chunks[key])
                    end
                end
            end
        end
        for _, c in ipairs(order) do
            local key = c.cx .. "," .. c.cy
            local victims = nil
            if not (fullUpTo[key] and fullUpTo[key] >= z) then
                victims = victimsInChunk(c.cx, c.cy, z, vr, isAreaRect, isMust, rectsCache)
            end
            if not victims then
                -- ja coberto pelo ponto de um andar de baixo
            elseif #victims == 0 then
                table.insert(points, { x = c.cx * s + 3, y = c.cy * s + 3, z = z, cx = c.cx, cy = c.cy })
                fullUpTo[key] = z + vr
            else
                local isVictim = {}
                for _, v in ipairs(victims) do isVictim[v.x .. "," .. v.y] = true end
                local targets = {}
                for y = c.cy * s, c.cy * s + s - 1 do
                    for x = c.cx * s, c.cx * s + s - 1 do
                        local must = isMust(x, y, z)
                        local inArea = must
                        if not inArea then
                            for _, r in ipairs(list) do
                                if rectHas(r, x, y) then
                                    inArea = true
                                    break
                                end
                            end
                        end
                        -- chao de zona colado no vizinho: protegido, fica sem energia
                        if inArea and (must or not isVictim[x .. "," .. y]) then
                            table.insert(targets, { x = x, y = y, must = must })
                        end
                    end
                end
                for _, p in ipairs(pickPoints(c.cx, c.cy, z, radius, targets, victims)) do
                    table.insert(points, { x = p.x, y = p.y, z = z, cx = c.cx, cy = c.cy })
                end
            end
        end
    end
    return points
end

--- Versao antiga (Fase 1-5): cada ponto ia pra todos os chunks que o circulo
--- toca -- vazava pros vizinhos. Mantida so pra comparacao/testes.
function KP.coverPointsCircles(rects, radius)
    local side = math.max(1, math.floor(radius * 1.41421356) - 1)
    local byZ = {}
    for _, r in ipairs(rects) do
        byZ[r.z] = byZ[r.z] or {}
        table.insert(byZ[r.z], r)
    end
    local points = {}
    for z, list in pairs(byZ) do
        local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
        for _, r in ipairs(list) do
            x0 = math.min(x0, r.x); y0 = math.min(y0, r.y)
            x1 = math.max(x1, r.x + r.w - 1); y1 = math.max(y1, r.y + r.h - 1)
        end
        for cy = y0, y1, side do
            for cx = x0, x1, side do
                local cx1, cy1 = math.min(cx + side - 1, x1), math.min(cy + side - 1, y1)
                for _, r in ipairs(list) do
                    if r.x <= cx1 and r.x + r.w - 1 >= cx and r.y <= cy1 and r.y + r.h - 1 >= cy then
                        table.insert(points, { x = math.floor((cx + cx1) / 2), y = math.floor((cy + cy1) / 2), z = z })
                        break
                    end
                end
            end
        end
    end
    return points
end

-- ---------------------------------------------------------------------------
-- Registrar / remover pontos nos chunks
-- ---------------------------------------------------------------------------

--- Chunk carregado nas coordenadas (em chunks), ou nil.
--- Nao usa cell:getChunk: no servidor ele procura no mapa de chunks dos
--- jogadores locais (que o servidor nao tem) e sempre devolve nil. Pegar um
--- tile do chunk funciona dos dois lados (no servidor vai pro ServerMap).
local function chunkAt(cell, wx, wy, z)
    local s = KP.CHUNK_SIZE
    local sq = cell:getGridSquare(wx * s, wy * s, 0)
    if not sq and z ~= 0 then sq = cell:getGridSquare(wx * s, wy * s, z) end
    return sq and sq:getChunk() or nil
end

--- Chama fn(chunk) pra cada chunk CARREGADO que o circulo do ponto toca.
local function forEachChunkOf(point, radius, fn)
    local cell = getCell()
    if not cell then return end
    local s = KP.CHUNK_SIZE
    for wy = math.floor((point.y - radius) / s), math.floor((point.y + radius) / s) do
        for wx = math.floor((point.x - radius) / s), math.floor((point.x + radius) / s) do
            local chunk = chunkAt(cell, wx, wy, point.z)
            if chunk then fn(chunk) end
        end
    end
end

--- Chunks de um ponto: so o dele (p.cx, p.cy) nos pontos novos; todos os que
--- o circulo toca nos pontos antigos (sem cx -- ate serem recalculados).
local function forEachChunkOfPoint(p, radius, fn)
    if p.cx then
        local cell = getCell()
        local chunk = cell and chunkAt(cell, p.cx, p.cy, p.z)
        if chunk then fn(chunk) end
    else
        forEachChunkOf(p, radius, fn)
    end
end

function KP.addPoints(points)
    local radius = KP.generatorRadius()
    for _, p in ipairs(points) do
        forEachChunkOfPoint(p, radius, function(chunk) chunk:addGeneratorPos(p.x, p.y, p.z) end)
    end
end

function KP.removePoints(points)
    local radius = KP.generatorRadius()
    for _, p in ipairs(points) do
        forEachChunkOfPoint(p, radius, function(chunk) chunk:removeGeneratorPos(p.x, p.y, p.z) end)
    end
end

--- Coordenadas do chunk no mapa (em chunks). O IsoChunk so expoe wx/wy como
--- campos, que o Lua nao enxerga: pega um tile de dentro dele (coordenadas
--- locais 0..7) e divide a posicao do tile pelo tamanho do chunk.
function KP.chunkCoords(chunk)
    local z = 0
    if z < chunk:getMinLevel() or z > chunk:getMaxLevel() then z = chunk:getMinLevel() end
    local sq = chunk:getGridSquare(0, 0, z)
    if not sq then return nil end
    return math.floor(sq:getX() / KP.CHUNK_SIZE), math.floor(sq:getY() / KP.CHUNK_SIZE)
end

--- So os pontos que tocam um chunk especifico (usado quando ele carrega).
function KP.addPointsToChunk(points, chunk)
    local radius = KP.generatorRadius()
    local s = KP.CHUNK_SIZE
    local wx0, wy0 = KP.chunkCoords(chunk)
    if not wx0 then return end
    for _, p in ipairs(points) do
        local touches
        if p.cx then
            touches = p.cx == wx0 and p.cy == wy0
        else
            touches = math.floor((p.x - radius) / s) <= wx0 and math.floor((p.x + radius) / s) >= wx0
                and math.floor((p.y - radius) / s) <= wy0 and math.floor((p.y + radius) / s) >= wy0
        end
        if touches then chunk:addGeneratorPos(p.x, p.y, p.z) end
    end
end

--- "Acorda" os aparelhos da area pra perceberem que ganharam/perderam energia.
function KP.refreshRects(rects)
    local cell = getCell()
    if not cell then return end
    for _, r in ipairs(rects) do
        for y = r.y, r.y + r.h - 1 do
            for x = r.x, r.x + r.w - 1 do
                local sq = cell:getGridSquare(x, y, r.z)
                if sq then
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        objects:get(i):checkHaveElectricity()
                    end
                end
            end
        end
    end
end
