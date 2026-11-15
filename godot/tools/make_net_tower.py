"""Делает спрайты башни «Сеть» из спрайтов зенитки: сдвиг оттенка в бирюзово-зелёный.
Запуск из папки godot: python tools/make_net_tower.py"""
import colorsys
import json
import os
from PIL import Image

SRC = "assets/custom_towers"
HUE_SHIFT = 128 / 360.0  # оранжевый -> морская волна
SAT = 1.05


def shift(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            # серый камень не трогаем, красим только насыщенные цвета
            if s > 0.18:
                h = (h + HUE_SHIFT) % 1.0
                s = min(1.0, s * SAT)
            r2, g2, b2 = colorsys.hsv_to_rgb(h, s, v)
            px[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return img


for part in ["base", "weapon", "projectile", "impact"]:
    shift(Image.open(f"{SRC}/flak_{part}.png")).save(f"{SRC}/net_{part}.png")

path = f"{SRC}/custom_towers.json"
data = json.load(open(path, encoding="utf-8"))
flak = json.dumps(data["towers"]["flak"]).replace("flak_", "net_")
data["towers"]["net"] = json.loads(flak)
with open(path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
print("готово")
