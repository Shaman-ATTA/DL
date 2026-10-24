# Skeletal (cutout) animation (v1.4.0: separate parts)

## v1.4 change: cutout parts instead of one skinned mesh
- `tools/cut_parts.py` splits the original sprite into one PNG per bone (`assets/parts/<id>/`), using the same bone segments as rigs.gd. Near each joint, the part drawn *below* gets the area hidden under the part above painted in (nearest-colour fill, blurred, darkened like an occlusion shadow). The part above gets a 3 px real-pixel feather. White background leftovers baked into the goblin and lich sprites are removed. It also writes `scripts/part_rects.gd` (rect and z per part).
- SkelActor creates one Sprite2D per part under a single `Parts` node, sorted by (z, bone order), and each part follows its bone through RemoteTransform2D. This avoids z_index fighting with the rest of the scene.
- Every part has its own ShaderMaterial. The `region` uniform maps the part's UV back to full-sprite UV, so wounds and the dissolve noise stay on the right body part. The rim light uses the full-sprite silhouette (`full_tex`), so cut edges do not glow.
- Bone rotations in clips are scaled by the rig's `amp` (hero 1.55, monsters 1.5). The root and weapon bones are not scaled. `hit_l` is a 40 % copy of `hit` and plays on normal taps.
- After changing bones or z in rigs.gd, re-run `python3 tools/cut_parts.py`, then `godot45 --headless --import`.


## Abstraction
- `Actor` (scripts/actor.gd): the legacy character. It is a single sprite with shader-driven breathing, springs, wounds and dissolve. It still drives every character that is not rigged.
- `SkelActor extends Actor` (scripts/skel_actor.gd) has the same public API (setup, kick, attack, set_param, set_wounds, add_blade, size), so main.gd needs no special cases beyond the optional calls `entrance()`, `die()` and `play_clip()`.
  - Node tree: Body (springs) → Root (AnimationPlayer) → skinned Polygon2D + Skeleton2D/Bone2D.
  - The mesh is a grid over the opaque pixels of the existing sprite. Weights are inverse distance^4 to the bone segments, top 3 kept. The art is unchanged.
  - Wounds and flash/dissolve live in `assets/shaders/skel.gdshader`. Wounds are in UV space, so they move with the bones.
- `Rigs` (scripts/rigs.gd) holds pure data per character: bones (joint, tip, greed, jiggle flags) and clips (keys per bone, smear windows). `Rigs.SKELETAL` lists which enemy ids use SkelActor. main.gd keeps a pool (`enemy_pool`: "legacy" plus one SkelActor per rig) and swaps visibility on spawn.

## Converting a character
1. Add a rig dictionary to rigs.gd: bones with joint/tip pixel coordinates measured on the sprite, plus the clips idle/attack/hit/death (and entrance for bosses).
2. Add the id to `Rigs.SKELETAL`.
3. Check it with `godot45 ... --write-movie ... res://scenes/preview_skel.tscn -- --rig=<id>`.

Estimates (per character, including tuning):
| character | estimate | notes |
|---|---|---|
| slime | 0.5–1 h | 3–4 bones, mostly squash and jiggle |
| mushroom | 1–1.5 h | cap is a jiggle bone |
| golem | 1.5–2 h | rigid parts stretch badly; would prefer split sprites |
| salamander | 2–3 h | tail chain of 4–5 bones |
| wraith | 1.5–2 h | cloth/tail jiggle chain |
| boss_dragon | 3–4 h | wings, neck and tail chains |
| boss_frostking | 2–3 h | humanoid plus cape |
| boss_wyrm | 3–4 h | long serpentine chain |
| pets (each) | 0.5–1 h | small, few bones |

## Known limitations
- The parts are cut from the original art, not redrawn. The painted-in joint areas are smeared colour fills and look like soft dark blobs when a part rotates far (most visible on the lich's head in hit/death).
- Not yet profiled on a real device.
