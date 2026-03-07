# Animation Retargeting Issues

## Goal

Transfer animations from rigged Sketchfab cat models (Somali Cat, Black Cat) onto our lowpoly cat model, so we can have Idle, Walk, Sit, etc. animations without creating them from scratch.

## Models Involved

| Model | Source | Skeleton | Animations | Orientation |
|-------|--------|----------|------------|-------------|
| **Our Cat** (Lowpoly) | [Sketchfab](https://sketchfab.com/3d-models/lowpoly-cat-rig-run-animation-c36df576c9ae4ed28e89069b1a2f427a) | 20 bones, linear hierarchy (pelvis→spine→head) | Run only | Faces +X |
| **Somali Cat** | [Sketchfab](https://sketchfab.com/3d-models/somali-cat-animated-ver-12-e185c3fd92b64c32b4515a32b29252fc) | Different bone count, branching hierarchy (spine branches from middle) | Idle, SitDown, SittingIdle, StandUp, WalkClean | Faces +Y |
| **Black Cat** | [Sketchfab](https://sketchfab.com/3d-models/black-cat-7cb7fb1f25794fb88c06b8b38f9d3822) | Blender metarig-based | Idle, Run, SlowWalk, Walk | Faces +Z |

## Core Problem

The three skeletons are fundamentally incompatible:
- **Different bone orientations** — rest poses have completely different rotations per bone
- **Different hierarchies** — Our Cat has a linear chain (pelvis→spine1→spine2→...→head), Somali Cat branches from the middle
- **Different world-space orientations** — each model faces a different axis
- **Our Cat's rest pose is NOT a standing cat** — the "standing" shape only exists inside the Run animation at frame 0. The bind/rest pose is a collapsed rig that only makes sense when the Run animation is applied.

## Approaches Tried

### 1. Runtime Retargeting in GDScript (Local Delta)

**Idea**: Extract per-bone rotation deltas from the source skeleton's animation and apply them to our skeleton.

```
delta = source_rest_rot.inverse() * source_anim_rot
dest_bone_rot = dest_rest_rot * delta
```

**Result**: Completely distorted. The delta assumes bones share the same local coordinate system, but they don't. A "rotate head left" delta from the Somali Cat means something entirely different when applied to Our Cat's head bone because the rest orientations differ by arbitrary rotations.

### 2. Runtime Retargeting in GDScript (Global Space)

**Idea**: Convert source bone rotations to global space, then back to the destination's local space.

```
global_rot = source_parent_global * source_local_rot
dest_local_rot = dest_parent_global.inverse() * global_rot
```

**Result**: Still distorted. The global-space rotation of "head facing forward" differs between skeletons because they face different directions in world space. Applying the Somali Cat's global head rotation to Our Cat just rotates the head to face the wrong axis.

### 3. Runtime Retargeting with Correction Quaternion

**Idea**: Pre-compute a correction quaternion per bone to account for the rest pose difference.

```
correction = dest_rest_global * source_rest_global.inverse()
dest_rot = correction * source_global_rot
```

**Result**: Partially worked for some bones but others were wildly wrong. The correction assumes the bones "mean the same thing" at rest, which isn't true when the hierarchies and rest poses are structurally different.

### 4. Blended Retargeting (Weighted Mix)

**Idea**: Blend between local delta and corrected global approaches.

**Result**: Just blended two wrong answers together. Slightly less wrong but still not usable.

### 5. Blender Constraint-Based Retargeting

**Idea**: In Blender, add Copy Rotation constraints (World Space) from source bones to destination bones, then bake the constrained animation into new keyframes using NLA bake with `visual_keying=True`.

**Result**: The constraint approach worked in principle, but:
- Blender's Action API changed in 4.x (uses `layers` and `slots` instead of `fcurves` and `groups`)
- `transform_apply` on armatures didn't modify bone positions as expected
- The baked animation was still distorted because the world-space rotations don't transfer correctly between differently-oriented skeletons
- Exported the baked animation to `cat_animated.gltf` but it was unusable

### 6. Manual Bone Mapping with Rest Pose Capture

**Idea**: Instead of using the bind rest pose, capture Our Cat's bone rotations at Run animation frame 0 (which is the actual "standing" pose), use that as the base, and apply deltas on top.

**Result**: This fixed the idle/standing pose issue — Our Cat now stands correctly. However, retargeting deltas from other skeletons on top of this base still produced distortion for the same fundamental reasons (incompatible bone orientations).

## Why It's Hard

Animation retargeting between arbitrary skeletons is a well-known hard problem in game development. It works well when:
- Both skeletons share the same bone naming convention (e.g., Mixamo→Mixamo)
- Both skeletons were created with the same rest pose (T-pose or A-pose)
- Both skeletons face the same direction

None of these conditions hold for our models. Professional solutions (Unreal Engine's IK Retargeter, Mixamo auto-retarget, Rokoko) handle this with:
- IK-based retargeting (solve for end-effector positions, not bone rotations)
- Manual per-bone twist/offset corrections in a visual editor
- Standardized intermediate skeleton formats

## Current State

- **Animation comparison viewer** (`compare_anims.tscn`) lets you view all three models side by side with per-model animation controls, drag-to-rotate camera, and scroll-to-zoom
- **Our Cat** only has the Run animation (and derived Walk at 0.35x speed, Idle from frame 0)
- **Somali Cat** and **Black Cat** play their native animations correctly on their own meshes
- Cross-skeleton retargeting is **not working** — would need either:
  1. A proper IK-based retargeting system
  2. Manually re-rigging the models to share a skeleton in Blender
  3. Hand-animating Our Cat directly in Blender
  4. Using Mixamo or similar service to standardize all skeletons first

## GDScript Gotchas Encountered

- **Type inference fails on Dictionary access**: `var x := dict["key"]` fails because the return type is `Variant`. Must use `var x: int = dict["key"]` with explicit type.
- **`set_bone_pose_rotation()` is absolute, not delta**: It sets the bone's rotation directly, not relative to rest. To apply a delta, you must compose: `rest_rot * delta_rot`.
- **`AnimationPlayer.seek()` doesn't update bones synchronously**: Calling `seek(0)` then immediately reading bone poses returns stale data. Must wait until the next `_process()` frame.
- **`_find_node_by_class()` needed for runtime model loading**: glTF imports nest the AnimationPlayer and Skeleton3D inside the scene tree unpredictably. A recursive search by class name is required.

## Lessons Learned

1. **Check skeleton compatibility BEFORE attempting retargeting** — compare bone counts, naming, rest poses, and orientations first
2. **Capture the "real" rest pose from animation frame 0** if the bind pose doesn't represent a natural stance
3. **Side-by-side comparison tools are invaluable** for debugging animation issues — build them early
4. **Runtime retargeting in GDScript is feasible for compatible skeletons** but not for arbitrary ones — use Blender or a dedicated retargeting tool for incompatible rigs
5. **Sketchfab models vary wildly in rig quality and convention** — downloading multiple models and comparing them is essential before committing to an approach
