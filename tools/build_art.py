"""Gera toda a arte do quadro de energia a partir do modelo do Blockbench.

Entrada: art/fuse_box.obj + art/fuse_box.png (exportados do Blockbench, Y pra
cima, 16 px = 1 tile; a porta virada pra -Z e o fundo em +Z, rente a borda).

Saida (dentro de mod/KnoxPower):
  42/media/texturepacks/KnoxPower.pack   sprites isometricos (formato PZPK v1)
  42/media/knoxpower.tiles               definicao dos tiles (formato tdef v1)
  42/media/textures/Item_KnoxPowerPanel*.png   icones dos itens
  common/media/voxel-studio/...          modelos 3D pro Viewpoint (1a pessoa)

Uso:  python tools/build_art.py
Rodar de novo sempre que o modelo mudar (e depois o deploy.ps1).
"""
import io
import math
import os
import struct

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "art")
MOD = os.path.join(ROOT, "mod", "KnoxPower")

TILESET = "knoxpower_01"
# Ordem dos tiles no tileset: indice -> parede (propriedade attachedX do jogo)
DIRS = ["N", "W", "S", "E"]
# Altura (em tiles) da parte de baixo da caixa: ~1 m do chao
MOUNT_Z = 0.95
# Distancia do centro do tile ate a face da parede (medida nos modelos do Voxel Studio)
WALL_FACE = 0.42

# Projecao isometrica do B42 (tiles 2x: quadro 128x256, losango do chao 128x64 na base)
FRAME_W, FRAME_H = 128, 256
TILE_TOP = (64, 192)          # vertice de cima do losango do chao
HALF_W, HALF_H = 64, 32       # meio losango
UNIT_Z = 78.38                # px por tile de altura (192 px por andar = 2,45 tiles)
SS = 4                        # supersampling


# ---------------------------------------------------------------------------
# Modelo
# ---------------------------------------------------------------------------

def load_obj(path):
    """Le o OBJ do Blockbench: vertices, uvs, normais e faces (listas de (v, vt, vn))."""
    V, T, N, F = [], [], [], []
    for line in open(path, encoding="utf-8"):
        a = line.split()
        if not a:
            continue
        if a[0] == "v":
            V.append(tuple(map(float, a[1:4])))
        elif a[0] == "vt":
            T.append(tuple(map(float, a[1:3])))
        elif a[0] == "vn":
            N.append(tuple(map(float, a[1:4])))
        elif a[0] == "f":
            face = []
            for p in a[1:]:
                i = p.split("/")
                face.append((int(i[0]) - 1, int(i[1]) - 1, int(i[2]) - 1))
            F.append(face)
    return V, T, N, F


def to_world_north(V, N):
    """Blockbench -> mundo, caixa na parede NORTE do tile.

    Mundo (igual aos modelos do Voxel Studio): origem no centro do tile,
    +x leste, +y sul, +z pra cima, unidade = 1 tile. A caixa gira 180 graus
    (porta, que olha pra -Z no Blockbench, passa a olhar pro sul) -- girar e
    nao espelhar, pra placa de perigo nao sair invertida.
    """
    min_y = min(v[1] for v in V)
    back = max(v[2] for v in V)  # fundo da caixa (encosta na parede)
    wv = [(-x, -(z - back) - WALL_FACE, y - min_y + MOUNT_Z) for x, y, z in V]
    wn = [(-x, -z, y) for x, y, z in N]
    return wv, wn


def rotate(points, direction):
    """Gira (em volta do centro do tile) da parede norte pra parede `direction`."""
    def r(p):
        x, y, z = p
        if direction == "N":
            return (x, y, z)
        if direction == "W":
            return (y, -x, z)
        if direction == "S":
            return (-x, -y, z)
        return (-y, x, z)  # E
    return [r(p) for p in points]


def triangles(F, V, N):
    """Faces em triangulos, na ordem que bate com a normal (regra da mao direita)."""
    tris = []
    for face in F:
        for k in range(1, len(face) - 1):
            tri = [face[0], face[k], face[k + 1]]
            a, b, c = (V[t[0]] for t in tri)
            e1 = [b[i] - a[i] for i in range(3)]
            e2 = [c[i] - a[i] for i in range(3)]
            cross = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            n = N[tri[0][2]]
            if sum(cross[i] * n[i] for i in range(3)) < 0:
                tri = [tri[0], tri[2], tri[1]]
            tris.append(tri)
    return tris


# ---------------------------------------------------------------------------
# Render isometrico (software, z-buffer)
# ---------------------------------------------------------------------------

def shade(n):
    """Luz fixa no estilo dos sprites do jogo: topo claro, lados mais escuros."""
    x, y, z = n
    if z > 0.5:
        return 1.0
    if y > 0.5:
        return 0.88  # virado pro sul (aparece embaixo-esquerda)
    if x > 0.5:
        return 0.72  # virado pro leste (aparece embaixo-direita)
    return 0.6


def render_iso(V, T, N, tris, tex, scale=1.0, frame=(FRAME_W, FRAME_H), top=TILE_TOP):
    """Desenha o modelo (coordenadas do mundo, origem no centro do tile) num quadro."""
    W, H = frame[0] * SS, frame[1] * SS
    color = [[None] * W for _ in range(H)]
    depth = [[-1e9] * W for _ in range(H)]
    tw, th = tex.size
    px = tex.load()

    def project(p):
        X, Y, Z = p[0] + 0.5, p[1] + 0.5, p[2]  # canto do tile como origem
        sx = top[0] + (X - Y) * HALF_W * scale
        sy = top[1] + (X + Y) * HALF_H * scale - Z * UNIT_Z * scale
        d = 0.612 * (X + Y) + 0.5 * Z
        return sx * SS, sy * SS, d

    for tri in tris:
        n = N[tri[0][2]]
        # so faces viradas pra camera (sul-leste, de cima)
        if 0.612 * (n[0] + n[1]) + 0.5 * n[2] <= 0:
            continue
        light = shade(n)
        P = [project(V[t[0]]) for t in tri]
        UV = [T[t[1]] for t in tri]
        x0 = max(int(min(p[0] for p in P)), 0)
        x1 = min(int(max(p[0] for p in P)) + 1, W - 1)
        y0 = max(int(min(p[1] for p in P)), 0)
        y1 = min(int(max(p[1] for p in P)) + 1, H - 1)
        (ax, ay, ad), (bx, by, bd), (cx, cy, cd) = P
        area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if abs(area) < 1e-9:
            continue
        for yy in range(y0, y1 + 1):
            for xx in range(x0, x1 + 1):
                qx, qy = xx + 0.5, yy + 0.5
                w0 = ((bx - qx) * (cy - qy) - (cx - qx) * (by - qy)) / area
                w1 = ((cx - qx) * (ay - qy) - (ax - qx) * (cy - qy)) / area
                w2 = 1 - w0 - w1
                if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6:
                    continue
                d = w0 * ad + w1 * bd + w2 * cd
                if d <= depth[yy][xx]:
                    continue
                u = w0 * UV[0][0] + w1 * UV[1][0] + w2 * UV[2][0]
                v = w0 * UV[0][1] + w1 * UV[1][1] + w2 * UV[2][1]
                tx = min(max(int(u * tw), 0), tw - 1)
                ty = min(max(int((1 - v) * th), 0), th - 1)
                r, g, b, a = px[tx, ty]
                if a < 8:
                    continue
                depth[yy][xx] = d
                color[yy][xx] = (int(r * light), int(g * light), int(b * light), a)

    big = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bp = big.load()
    for yy in range(H):
        for xx in range(W):
            if color[yy][xx]:
                bp[xx, yy] = color[yy][xx]
    return big.resize(frame, Image.LANCZOS)


# ---------------------------------------------------------------------------
# Formatos do jogo
# ---------------------------------------------------------------------------

def pstr(s):
    b = s.encode("utf-8")
    return struct.pack("<i", len(b)) + b


def write_pack(path, page_name, sprites):
    """PZPK v1 com uma pagina: sprites = [(nome, imagem do quadro 128x256)]."""
    crops = []
    for name, frame in sprites:
        box = frame.getbbox()
        crops.append((name, frame.crop(box), box))
    pad = 2
    page_w = sum(c[1].width + pad for c in crops) + pad
    page_h = max(c[1].height for c in crops) + pad * 2
    page = Image.new("RGBA", (page_w, page_h), (0, 0, 0, 0))
    subs = b""
    x = pad
    for name, img, box in crops:
        page.paste(img, (x, pad))
        subs += pstr(name) + struct.pack("<8i", x, pad, img.width, img.height, box[0], box[1], FRAME_W, FRAME_H)
        x += img.width + pad
    png = io.BytesIO()
    page.save(png, "PNG")
    png = png.getvalue()
    data = b"PZPK" + struct.pack("<ii", 1, 1)
    data += pstr(page_name) + struct.pack("<ii", len(sprites), 1) + subs
    data += struct.pack("<i", len(png)) + png
    with open(path, "wb") as f:
        f.write(data)


def write_tiles(path, props_by_index, columns=8, rows=1):
    """tdef v1 com um tileset; props_by_index = {indice: [(chave, valor)]}."""
    data = b"tdef" + struct.pack("<ii", 1, 1)
    data += (TILESET + "\n").encode() + (TILESET + ".png\n").encode()
    count = columns * rows
    data += struct.pack("<iiii", columns, rows, 1, count)
    for i in range(count):
        props = props_by_index.get(i, [])
        data += struct.pack("<i", len(props))
        for k, v in props:
            data += (k + "\n" + v + "\n").encode()
    with open(path, "wb") as f:
        f.write(data)


def write_obj(path, V, T, N, tris, mtl_name):
    """OBJ no formato dos modelos do Viewpoint (Z pra cima, unidade = tile)."""
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Knox Power - gerado por tools/build_art.py (Z up, tile units)\n")
        f.write("mtllib %s\nusemtl atlas\n" % mtl_name)
        for v in V:
            f.write("v %.6f %.6f %.6f\n" % v)
        for t in T:
            f.write("vt %.6f %.6f\n" % t)
        for n in N:
            f.write("vn %.6f %.6f %.6f\n" % n)
        for tri in tris:
            f.write("f " + " ".join("%d/%d/%d" % (a + 1, b + 1, c + 1) for a, b, c in tri) + "\n")


# ---------------------------------------------------------------------------

def main():
    bbV, T, bbN, F = load_obj(os.path.join(ART, "fuse_box.obj"))
    tex = Image.open(os.path.join(ART, "fuse_box.png")).convert("RGBA")
    nV, nN = to_world_north(bbV, bbN)

    media42 = os.path.join(MOD, "42", "media")
    vs_dir = os.path.join(MOD, "common", "media", "voxel-studio", "knoxpower")
    os.makedirs(os.path.join(media42, "texturepacks"), exist_ok=True)
    os.makedirs(vs_dir, exist_ok=True)

    sprites, manifest = [], [
        "id=knox-power",
        "name=Knox Power models",
        "version=1",
    ]
    tex.save(os.path.join(vs_dir, "texture.png"))
    with open(os.path.join(vs_dir, "panel.mtl"), "w", encoding="utf-8") as f:
        f.write("newmtl atlas\nKd 1 1 1\nd 1\nmap_Kd texture.png\n")

    for i, d in enumerate(DIRS):
        V = rotate(nV, d)
        N = rotate(nN, d)
        tris = triangles(F, V, N)
        name = "%s_%d" % (TILESET, i)
        sprites.append((name, render_iso(V, T, N, tris, tex)))
        obj_name = "panel_%s.obj" % d.lower()
        write_obj(os.path.join(vs_dir, obj_name), V, T, N, tris, "panel.mtl")
        key = "knoxpower-panel-%s" % d.lower()
        manifest.append("model.%s=knoxpower/%s" % (key, obj_name))
        manifest.append("bind.%s=%s,0,0,0,0,1" % (name, key))

    write_pack(os.path.join(media42, "texturepacks", "KnoxPower.pack"), "KnoxPower0", sprites)
    write_tiles(os.path.join(media42, "knoxpower.tiles"),
                {i: [("attached" + d, "")] for i, d in enumerate(DIRS)})
    # Profundidade (B42): sem isso o jogo desenha o quadro NA FRENTE de quem esta
    # no tile. Usa os planos de parede que o jogo ja tem (os mesmos da caixa
    # eletrica vanilla; leste usa o plano leste de verdade, industry_02_185).
    depth = {"N": "industry_02_193", "W": "industry_02_194", "S": "industry_02_184", "E": "industry_02_185"}
    # o jogo so le esse arquivo da pasta common/media do mod (TileDepthTextureAssignmentManager.init)
    common_media = os.path.join(MOD, "common", "media")
    os.makedirs(common_media, exist_ok=True)
    with open(os.path.join(common_media, "tileDepthTextureAssignments.txt"), "w", encoding="utf-8") as f:
        f.write("tileDepthTextureAssignments\n{\n    VERSION = 1,\n")
        for i, d in enumerate(DIRS):
            f.write("    %s_%d = %s,\n" % (TILESET, i, depth[d]))
        f.write("}\n")
    with open(os.path.join(MOD, "common", "media", "voxel-studio", "knoxpower.properties"), "w", encoding="utf-8") as f:
        f.write("\n".join(manifest) + "\n")

    # Icones: o quadro de frente/lado (parede oeste, porta virada pra camera),
    # com o numero de disjuntores no canto
    V = rotate(nV, "W")
    N = rotate(nN, "W")
    big = render_iso(V, T, N, triangles(F, V, N), tex, scale=2.2, frame=(256, 720), top=(128, 660))
    big = big.crop(big.getbbox())
    font = None
    for candidate in ("arialbd.ttf", "arial.ttf"):
        try:
            font = ImageFont.truetype(candidate, 13)
            break
        except OSError:
            pass
    for size, count in (("Small", 4), ("Medium", 8), ("Large", 12)):
        icon = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        img = big.copy()
        img.thumbnail((30, 30), Image.LANCZOS)
        icon.alpha_composite(img, ((32 - img.width) // 2, (32 - img.height) // 2))
        draw = ImageDraw.Draw(icon)
        text = str(count)
        tw = draw.textlength(text, font=font)
        x, y = 31 - tw, 18
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                draw.text((x + ox, y + oy), text, font=font, fill=(0, 0, 0, 255))
        draw.text((x, y), text, font=font, fill=(255, 215, 60, 255))
        icon.save(os.path.join(media42, "textures", "Item_KnoxPowerPanel%s.png" % size))

    # previa pra conferir a olho (fora do mod)
    preview = Image.new("RGBA", (FRAME_W * 4, FRAME_H), (80, 80, 80, 255))
    draw = ImageDraw.Draw(preview)
    for i, (_, frame) in enumerate(sprites):
        x = i * FRAME_W
        draw.polygon([(x + 64, 192), (x + 128, 224), (x + 64, 256), (x, 224)], outline=(255, 255, 0, 255))
        preview.alpha_composite(frame, (x, 0))
    preview.save(os.path.join(ART, "preview_tiles.png"))
    print("ok: %d sprites, pack/tiles/modelos/icones gerados" % len(sprites))


if __name__ == "__main__":
    main()
