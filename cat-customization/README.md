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

## Scenes

- `main.tscn` — Cat customizer with fur shader, eye color, pattern controls
- `compare_anims.tscn` — Side-by-side 5-model animation comparison viewer
- `preview_anims.tscn` — Single model animation preview
- `debug_view.tscn` — Debug/UV visualization
