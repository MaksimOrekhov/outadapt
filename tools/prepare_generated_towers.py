"""Split generated 3x3 custom tower atlases into isolated source sprites.

Generated atlases are kept in godot/assets/custom_towers/source. The sprites
remain high resolution here; the Godot importer later downsamples them to the
game's fixed pixel dimensions with nearest-neighbour sampling.
"""
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "godot" / "assets" / "custom_towers" / "source"
BASES = SOURCE / "bases-atlas.png"
WEAPONS = SOURCE / "weapons-atlas.png"
BASE_CROPS = SOURCE / "base-crops"
WEAPON_CROPS = SOURCE / "weapon-crops"
OUT = ROOT / "godot" / "assets" / "custom_towers"
KINDS = [
    "arrow", "flak", "cannon",
    "poison", "frost", "tesla",
    "ember", "sniper", "beacon",
]
WEAPON_CUTS = [270, 280, 280, 280, 270, 260, 300, 300, 330]
MOUNTS = [22, 21, 19, 21, 19, 20, 19, 18, 19]


def crop_grid(path: Path, destination: Path) -> None:
    atlas = Image.open(path).convert("RGBA")
    destination.mkdir(parents=True, exist_ok=True)
    width, height = atlas.size
    for index, kind in enumerate(KINDS):
        row, col = divmod(index, 3)
        cell = atlas.crop((
            round(col * width / 3), round(row * height / 3),
            round((col + 1) * width / 3), round((row + 1) * height / 3),
        ))
        alpha = cell.getchannel("A")
        # Generated edge pixels can carry colored translucent fringes. Keep
        # solid pixel-art clusters and make the cutout alpha crisp.
        alpha = alpha.point(lambda value: 255 if value >= 144 else 0)
        cell.putalpha(alpha)
        bbox = cell.getchannel("A").getbbox()
        if bbox is None:
            raise ValueError(f"No sprite found in cell {index} ({kind})")
        sprite = cell.crop(bbox)
        pad = max(12, round(max(sprite.size) * 0.05))
        out = Image.new("RGBA", (sprite.width + 2 * pad, sprite.height + 2 * pad))
        out.alpha_composite(sprite, (pad, pad))
        out.save(destination / f"{kind}.png", optimize=True)
        print(f"{kind}: {sprite.width}x{sprite.height} -> {destination / f'{kind}.png'}")


def crop_weapon_grid(path: Path, destination: Path) -> None:
    atlas = Image.open(path).convert("RGBA")
    destination.mkdir(parents=True, exist_ok=True)
    width, height = atlas.size
    for index, kind in enumerate(KINDS):
        row, col = divmod(index, 3)
        bounds = (
            round(col * width / 3), round(row * height / 3),
            round((col + 1) * width / 3), round((row + 1) * height / 3),
        )
        cell = atlas.crop(bounds)
        cell = cell.crop((0, 0, cell.width, min(WEAPON_CUTS[index], cell.height)))
        alpha = cell.getchannel("A").point(lambda value: 255 if value >= 144 else 0)
        cell.putalpha(alpha)
        bbox = cell.getchannel("A").getbbox()
        if bbox is None:
            raise ValueError(f"No weapon head found in cell {index} ({kind})")
        sprite = cell.crop(bbox)
        pad = max(12, round(max(sprite.size) * 0.05))
        out = Image.new("RGBA", (sprite.width + 2 * pad, sprite.height + 2 * pad))
        out.alpha_composite(sprite, (pad, pad))
        out.save(destination / f"{kind}.png", optimize=True)
        print(f"{kind}: weapon {sprite.width}x{sprite.height} -> {destination / f'{kind}.png'}")


def fit_sprite(source: Image.Image, max_size: tuple[int, int]) -> Image.Image:
    source = source.convert("RGBA")
    bbox = source.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("Cannot fit an empty sprite")
    sprite = source.crop(bbox)
    max_w, max_h = max_size
    scale = min(max_w / sprite.width, max_h / sprite.height)
    size = (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale)))
    return sprite.resize(size, Image.Resampling.NEAREST)


def make_runtime_sprites() -> None:
    custom = {"towers": {}}
    for index, kind in enumerate(KINDS):
        base = fit_sprite(Image.open(BASE_CROPS / f"{kind}.png"), (62, 78))
        base_canvas = Image.new("RGBA", (64, 80))
        base_canvas.alpha_composite(base, ((64 - base.width) // 2, 80 - base.height))
        base_path = OUT / f"{kind}_base.png"
        base_canvas.save(base_path, optimize=True)

        weapon = fit_sprite(Image.open(WEAPON_CROPS / f"{kind}.png"), (88, 48))
        weapon_canvas = Image.new("RGBA", (96, 96))
        # The sprite's bottom-center pivot is aligned to the frame center so
        # the game can rotate it without rotating the platform underneath.
        weapon_canvas.alpha_composite(weapon, ((96 - weapon.width) // 2, 48 - weapon.height))
        weapon_path = OUT / f"{kind}_weapon.png"
        weapon_canvas.save(weapon_path, optimize=True)

        level = {
            "base": f"res://assets/custom_towers/{kind}_base.png",
            "base_size": [64, 80],
            "ground": 80,
            "mount": MOUNTS[index],
            "weapon": {
                "file": f"res://assets/custom_towers/{kind}_weapon.png",
                "frame": 96,
                "frame_h": 96,
                "frames": 1,
                "cols": 1,
                "idle": 1,
            },
        }
        custom["towers"][kind] = {"levels": [level, level, level]}
        print(f"runtime {kind}: base {base.width}x{base.height}, head {weapon.width}x{weapon.height}")

    (OUT / "custom_towers.json").write_text(
        __import__("json").dumps(custom, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    if not BASES.is_file():
        raise FileNotFoundError(BASES)
    crop_grid(BASES, BASE_CROPS)
    if WEAPONS.is_file():
        crop_weapon_grid(WEAPONS, WEAPON_CROPS)
        make_runtime_sprites()
