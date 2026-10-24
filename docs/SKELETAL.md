# Skeletal (cutout) animation — pilot (v1.3.0)

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
- A single mesh means there are no hidden pixels behind limbs. Large rotations stretch the neighbouring art, so clips keep rotations moderate.
- Not yet profiled on a real device.
