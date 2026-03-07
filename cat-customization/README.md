# Cat Customization

A real-time cat customizer built in Godot 4.6.1. Features procedural fur patterns via spatial shaders, 3D eye meshes attached to skeleton bones, and a full UI for tweaking colors, patterns, and animations.

## Features

- **6 fur patterns**: Solid, Tabby, Tuxedo, Calico, Siamese, Spotted
- **8 fur color presets**: Orange, Tuxedo, Calico, Siamese, Gray, White, Brown, Black
- **6 eye colors**: Green, Amber, Blue, Brown, Purple, Cyan
- **4 animation modes**: Stand (procedural idle), Loaf (procedural sphinx pose), Walk (0.35x run), Run
- **Pattern controls**: Intensity and scale sliders
- **UV-based region detection**: Custom shader classifies 14 discrete UV regions (body, face, ears, nose, eyes, tail, paws) using gradient-based boundary detection
- **3D eye spheres**: BoneAttachment3D on head bone with iris + pupil meshes

## Model Attribution

- **Lowpoly Cat** (Our Cat): [Lowpoly Cat Rig + Run Animation](https://sketchfab.com/3d-models/lowpoly-cat-rig-run-animation-c36df576c9ae4ed28e89069b1a2f427a) by [Daily Lowpoly](https://sketchfab.com/dailyfree3d), licensed under [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/).
- **Somali Cat**: [Somali Cat Animated ver 1.2](https://sketchfab.com/3d-models/somali-cat-animated-ver-12-e185c3fd92b64c32b4515a32b29252fc) by [DreamNoms](https://sketchfab.com/DreamNoms), licensed under [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/).
- **Black Cat**: [Black Cat](https://sketchfab.com/3d-models/black-cat-7cb7fb1f25794fb88c06b8b38f9d3822) by [Walistoteles](https://sketchfab.com/payssonl), licensed under [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/).
- **Cartoon Cat**: [Cartoon Cat](https://sketchfab.com/3d-models/cartoon-cat-4a738eaed9d34547a3f5a705a0e37c6a) by [Baydinman](https://sketchfab.com/Baydinman), licensed under [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/). Bipedal, 25 combat animations (sword/pistol/arm attacks, hit/death reactions, idle variations).
- **Little Cat**: [Little Cat](https://sketchfab.com/3d-models/little-cat-1e6f360989b04b53a393f398d5372205) by [Southport Art Studio](https://sketchfab.com/SouthportArtStudio), licensed under Sketchfab Free Standard. Chibi humanoid, 10 animations (idle, walk, run, jump, greeting, eat, sleep).

## Animation Inventory

| Model | Anims | Combat? | Animations |
|-------|-------|---------|------------|
| Our Cat | 1 | No | run |
| Somali Cat | 5 | No | Idle, SitDown, SittingIdle, StandUp, WalkClean |
| Black Cat | 4 | No | Idle, Run, SlowWalk, Walk |
| Cartoon Cat | 25 | **Yes** | Sword (Idle/Light/Medium/Hight/End), Pistol (Idle/Light/Medium/Hight/End), Arm (Idle/Light/Medium/Hight/End), Hit/Death per weapon type, 4 idle variations |
| Little Cat | 10 | No | TPose, Idle, Walk, Run, Jump, Greeting, Eat, Sleep x3 |

## Body Customization (Bone Scaling)

5 sliders control bone scale in real-time, applied on top of animations each frame:

| Slider | Bones | Range | Default |
|--------|-------|-------|---------|
| Head | `Head_05` | 0.75–1.25 | 1.0 |
| Eyes | `Aye_L_06`, `Aye_R_021` | 0.6–1.4 | 1.0 |
| Eye Gap | `Aye_L_06`, `Aye_R_021` (position.x) | 0.8–1.2 | 1.0 |
| Body | `Bone2_02`, `Bone3_03` (X/Z only) | 0.7–1.3 | 1.0 |
| Tail | `Tail_B1–B5_040–044` | 0.0–2.0 | 1.0 |

All slider ranges are symmetric around 0.5 so the midpoint (0.5) maps to scale 1.0 (unmodified model).

## Known Issues & Lessons Learned

### Bone scaling vs AnimationPlayer (process_priority)
**Problem**: `set_bone_pose_scale()` in `_process()` had no visible effect — the model didn't change when sliders moved.
**Root cause**: AnimationPlayer also runs during `_process()` and overwrites bone poses every frame. If our script's `_process` runs *before* the AnimationPlayer, our scale changes are immediately overwritten.
**Fix**: Set `process_priority = 100` in `_ready()` so our `_process` runs *after* AnimationPlayer (which defaults to priority 0). We read the animation's bone scale and multiply our custom scale on top: `set_bone_pose_scale(idx, anim_scale * custom)`.

### Slider initial values must match the midpoint, not the max
**Problem**: Default model looked distorted on startup — oversized eyes, doubled tail, wide body — even though all slider labels showed "1.0".
**Root cause**: `bone_scale_values` dictionary was initialized with all values at `1.0`, but the lerp ranges treat `0.5` as the "scale = 1.0" midpoint. When `_update_bone_scales("head_size", 0.5)` was called in `_ready()`, it only set `head_size` to 0.5 — the other values stayed at 1.0 (their init), which mapped to the *maximum* of each range (eyes=1.4×, body=1.3×, tail=2.0×).
**Fix**: Initialize all values to `0.5` so every bone starts at scale 1.0.

### GDScript closures don't capture loop variables
**Problem**: Slider `value_changed` signals connected via `func(v): _update_bone_scales(sname, v)` in a loop never fired.
**Root cause**: GDScript lambdas in loops don't reliably capture the loop variable. The closure may reference a stale or wrong value.
**Fix**: Use `.bind()` instead: `slider.value_changed.connect(_on_bone_slider.bind(sname))` with a separate method `_on_bone_slider(value, slider_name)`.

### Fur shader transparency/clipping
**Problem**: Fur appeared semi-transparent — internal geometry (legs, body cavity) was visible through the surface.
**Root cause**: The fur recolor shader included `ALPHA = tex.a;` which enabled alpha blending on the material, making it transparent where the texture alpha wasn't exactly 1.0.
**Fix**: Remove the `ALPHA` line entirely — the shader only needs to output `ALBEDO`.

### Color presets must be independent
**Problem**: Clicking a primary color swatch also changed the stripe color (and vice versa).
**Root cause**: Both rows shared the same `_apply_preset(i)` function which set both primary and secondary colors from a paired array.
**Fix**: Separate into independent `primary_colors`/`stripe_colors` arrays with dedicated `_apply_primary()`/`_apply_stripe()` functions.

## Scenes

- `main.tscn` — Cat customizer with fur shader, eye color, pattern controls, bone scaling
- `compare_anims.tscn` — Side-by-side 5-model animation comparison viewer
- `preview_anims.tscn` — Single model animation preview
- `debug_view.tscn` — Debug/UV visualization
