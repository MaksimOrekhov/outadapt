"""Импорт пакета Spire (Foozle, CC0) в проект Godot.

Читает распакованные архивы из assets_src/spire/x, нарезает листы на кадры, перекрашивает
башни под наши типы и пишет godot/assets/spire/*.png + spire.json. В игре спрайты
масштабируются ближайшим соседом, чтобы сохранить чёткие края пиксель-арта.

Запуск: python tools/import_spire.py   (нужен Pillow)
"""
import colorsys
import glob
import json
import os
import shutil

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets_src", "spire", "x")
OUT = os.path.join(ROOT, "godot", "assets", "spire")
SCALE = 1

meta = {"scale": SCALE, "towers": {}, "enemies": {}, "fx": {}, "tiles": {}}


def find(pattern):
    hits = sorted(glob.glob(os.path.join(SRC, "**", pattern), recursive=True))
    if not hits:
        raise FileNotFoundError(pattern)
    return hits[0]


MAX_W = 8192


def scale_for(frame_px):
    """Мелкий пиксель-арт увеличиваем сильнее, крупные кадры — вдвое (экономим память)."""
    return SCALE


def up(im, sc=SCALE):
    return im.resize((im.width * sc, im.height * sc), Image.NEAREST)


def save(im, rel, sc=SCALE):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    up(im, sc).save(path)
    return rel.replace(os.sep, "/")


# ── перекраска ────────────────────────────────────────────────

def recolor(im, rules):
    """rules: [(h_from, h_to, h_target)] в градусах; меняем оттенок насыщенных пикселей в диапазоне."""
    if not rules:
        return im
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s < 0.28 or v < 0.2:
                continue
            deg = h * 360
            for lo, hi, tgt in rules:
                inside = lo <= deg <= hi if lo <= hi else (deg >= lo or deg <= hi)
                if inside:
                    nr, ng, nb = colorsys.hsv_to_rgb(tgt / 360, min(1, s * 1.05), v)
                    px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
                    break
    return im


# ── нарезка ───────────────────────────────────────────────────

def alpha_rows(im):
    a = im.getchannel("A")
    w, h = im.size
    data = a.load()
    return [any(data[x, y] > 0 for x in range(w)) for y in range(h)]


def frames_of(sheet):
    """Лист оружия/снаряда: 1 ряд (кадр h×h) или 2 ряда (покой + атака, кадр h/2)."""
    w, h = sheet.size
    rows = 1
    f = h
    two_rows = False
    if h % 2 == 0 and w % (h // 2) == 0 and h >= 64:
        occ = alpha_rows(sheet)
        mid = h // 2
        two_rows = any(occ[:mid]) and any(occ[mid:]) and not any(occ[mid - 2: mid + 2])
    if not two_rows and w % h != 0:
        # не делится на квадратные кадры (стрела 24×40 и т.п.) — это один кадр
        return [[sheet]], w
    if two_rows:
        occ = alpha_rows(sheet)
        mid = h // 2
        band = occ[mid - 2: mid + 2]
        top = any(occ[:mid])
        bot = any(occ[mid:])
        if top and bot and not any(band):
            rows, f = 2, h // 2
    out = []
    for r in range(rows):
        row = []
        for c in range(w // f):
            fr = sheet.crop((c * f, r * f, (c + 1) * f, (r + 1) * f))
            if fr.getbbox():
                row.append(fr)
        out.append(row)
    return out, f


def strip(frames, sc=SCALE):
    """Кадры сеткой: не шире MAX_W после увеличения. Возвращает (картинка, колонок)."""
    f = frames[0].width
    fh = frames[0].height
    cols = max(1, min(len(frames), MAX_W // (f * sc)))
    rows = (len(frames) + cols - 1) // cols
    s = Image.new("RGBA", (f * cols, fh * rows))
    for i, fr in enumerate(frames):
        s.paste(fr, ((i % cols) * f, (i // cols) * fh))
    return s, cols


def sheet_anim(path, rules, rel):
    """Анимация из листа → одна полоса кадров; idle — сколько первых кадров покоя."""
    im = recolor(Image.open(path).convert("RGBA"), rules)
    rows, f = frames_of(im)
    if len(rows) == 2:
        frames = rows[0] + rows[1]
        idle = len(rows[0])
    else:
        frames = rows[0]
        idle = 1
    sc = scale_for(max(f, frames[0].height))
    img, cols = strip(frames, sc)
    return {"file": save(img, rel, sc), "frame": frames[0].width * sc, "frame_h": frames[0].height * sc,
            "frames": len(frames), "idle": idle, "cols": cols, "scale": sc}


# ── башни ─────────────────────────────────────────────────────

# наш тип → (номер башни Spire, правила перекраски по уровням [ур1, ур2, ур3])
BLUE = (165, 235)
TOWERS = {
    "arrow": (1, [[], [], []]),
    "flak": (1, [[(165, 235, 28)], [(165, 235, 28)], [(165, 235, 28)]]),
    "cannon": (4, [[], [], []]),
    "poison": (3, [[(265, 360, 105), (0, 15, 105)], [], [(265, 360, 105), (0, 15, 105)]]),
    "frost": (5, [[], [(290, 360, 195), (0, 20, 195)], [(290, 360, 200), (0, 20, 200)]]),
    "tesla": (2, [[], [(15, 60, 212)], [(50, 140, 272)]]),
    "ember": (7, [[(165, 235, 14)], [], [(60, 150, 36)]]),
    "sniper": (6, [[], [], []]),
    "beacon": (8, [[], [], []]),
}


def mount_point(base):
    """Где на основании стоит оружие: центр верхней площадки."""
    a = base.getchannel("A").load()
    w, h = base.size
    for y in range(h):
        width = sum(1 for x in range(w) if a[x, y] > 0)
        if width >= w * 0.55:
            return int(y + w * 0.30)
    return h // 3


for kind, (n, rules) in TOWERS.items():
    bases = Image.open(find("Tower %02d.png" % n)).convert("RGBA")
    bw = bases.width // 3
    t = {"levels": []}
    for lv in range(3):
        base = recolor(bases.crop((lv * bw, 0, (lv + 1) * bw, bases.height)), rules[lv])
        bb = base.getbbox()
        lvl = {
            "base": save(base, "towers/%s_base_%d.png" % (kind, lv + 1)),
            "base_size": [base.width * SCALE, base.height * SCALE],
            "ground": bb[3] * SCALE,
            "mount": mount_point(base) * SCALE,
        }
        wp = glob.glob(os.path.join(SRC, "**", "Tower %02d - Level %02d - Weapon.png" % (n, lv + 1)), recursive=True)
        if wp:
            lvl["weapon"] = sheet_anim(wp[0], rules[lv], "towers/%s_weapon_%d.png" % (kind, lv + 1))
        pj = glob.glob(os.path.join(SRC, "**", "Tower %02d - Level %02d - Projectile.png" % (n, lv + 1)), recursive=True) \
            or glob.glob(os.path.join(SRC, "**", "Tower %02d - Level X - Projectile.png" % n), recursive=True)
        if pj:
            lvl["projectile"] = sheet_anim(pj[0], rules[lv], "towers/%s_proj_%d.png" % (kind, lv + 1))
        im_ = glob.glob(os.path.join(SRC, "**", "Tower %02d - Level %02d - Projectile - Impact.png" % (n, lv + 1)), recursive=True) \
            or glob.glob(os.path.join(SRC, "**", "Tower %02d - Level X - Projectile - Impact.png" % n), recursive=True) \
            or glob.glob(os.path.join(SRC, "**", "Tower %02d - Weapon - Impact.png" % n), recursive=True)
        if im_:
            lvl["impact"] = sheet_anim(im_[0], rules[lv], "towers/%s_impact_%d.png" % (kind, lv + 1))
        t["levels"].append(lvl)
    meta["towers"][kind] = t
    print("башня", kind, "<- Tower %02d" % n)


# ── враги ─────────────────────────────────────────────────────

# 9 рядов: движение / удар / смерть × (вверх, вниз, вбок); кадр 64×64
ENEMIES = ["Leafbug", "Scorpion", "Magma Crab", "Firebug", "Clampbeetle", "Firewasp", "Flying Locust", "Voidbutterfly"]
for name in ENEMIES:
    sh = Image.open(find(name + ".png")).convert("RGBA")
    f = sh.height // 9
    key = name.lower().replace(" ", "_")
    rows = []
    out = Image.new("RGBA", (sh.width, sh.height))
    out.paste(sh, (0, 0))
    for r in range(sh.height // f):
        cnt = 0
        for c in range(sh.width // f):
            if sh.crop((c * f, r * f, (c + 1) * f, (r + 1) * f)).getbbox():
                cnt = c + 1
        rows.append(cnt)
    meta["enemies"][key] = {"file": save(out, "enemies/%s.png" % key), "frame": f * SCALE, "rows": rows,
                            "fly": name in ["Clampbeetle", "Firewasp", "Flying Locust", "Voidbutterfly"]}
    print("враг", key, rows)


# ── эффекты ───────────────────────────────────────────────────

def folder_anim(folder, rel):
    files = sorted(glob.glob(os.path.join(folder, "*.png")))
    frames = [Image.open(p).convert("RGBA") for p in files]
    w = max(fr.width for fr in frames)
    h = max(fr.height for fr in frames)
    norm = []
    for fr in frames:
        c = Image.new("RGBA", (w, h))
        c.paste(fr, ((w - fr.width) // 2, (h - fr.height) // 2))
        norm.append(c)
    sc = scale_for(max(w, h))
    img, cols = strip(norm, sc)
    return {"file": save(img, rel, sc), "frame": w * sc, "frame_h": h * sc, "frames": len(frames), "cols": cols, "scale": sc}


mag = os.path.dirname(find("Pixel_Magic_Effects_Animations.png"))
for d in sorted(os.listdir(mag)):
    p = os.path.join(mag, d)
    if os.path.isdir(p) and d != "Icons":
        meta["fx"][d.lower()] = folder_anim(p, "fx/%s.png" % d.lower())
        print("эффект", d.lower())

# постройка и разрушение башни (лист-сетка 192×192)
for nm, key in [("Tower Construction.png", "construct"), ("Tower - Collapse.png", "collapse")]:
    sh = Image.open(find(nm)).convert("RGBA")
    f = 192
    frames = []
    for r in range(sh.height // f):
        for c in range(sh.width // f):
            fr = sh.crop((c * f, r * f, (c + 1) * f, (r + 1) * f))
            if fr.getbbox():
                frames.append(fr)
    sc = scale_for(f)
    img, cols = strip(frames, sc)
    meta["fx"][key] = {"file": save(img, "fx/%s.png" % key, sc), "frame": f * sc, "frame_h": f * sc, "frames": len(frames), "cols": cols, "scale": sc}
    print("эффект", key, len(frames))


# ── тайлы ─────────────────────────────────────────────────────

ts = Image.open(find("Grass Tileset.png")).convert("RGBA")
T = 64


def tile(cx, cy, w=1, h=1):
    return ts.crop((cx, cy, cx + T * w, cy + T * h))


TILES = {
    # дорога: прямые и повороты из «кольца» (704..960, 64..320); трава — левый лист креста
    "grass": (64, 128),
    "road_h": (768, 64),
    "road_v": (576, 128),
    "corner_rd": (704, 64),   # соединяет вправо и вниз
    "corner_ld": (896, 64),   # влево и вниз
    "corner_ru": (704, 256),  # вправо и вверх
    "corner_lu": (896, 256),  # влево и вверх
}
for k, (x, y) in TILES.items():
    meta["tiles"][k] = save(tile(x, y), "tiles/%s.png" % k)
# декор: деревья 64×64, камни, трава
DECOR = {
    "tree_green": [(832, 384), (896, 384), (832, 448), (896, 448)],
    "tree_autumn": [(832, 576), (896, 576), (832, 640), (896, 640)],
    "rock": [(832, 768), (896, 768), (832, 832), (896, 832)],
    "tuft": [(704, 576), (768, 576)],
}
def clean(im):
    # в листе между деревьями проходит тонкая разделительная линия — срезаем край
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(3):
            px[x, y] = (0, 0, 0, 0)
    return im


for k, cells in DECOR.items():
    meta["tiles"][k] = [save(clean(tile(x, y)), "tiles/%s_%d.png" % (k, i)) for i, (x, y) in enumerate(cells)]

with open(os.path.join(OUT, "spire.json"), "w", encoding="utf-8") as fp:
    json.dump(meta, fp, ensure_ascii=False, indent=1)
shutil.copy(find("Readme.txt"), os.path.join(OUT, "LICENSE_Spire_CC0.txt"))
print("готово:", OUT)
