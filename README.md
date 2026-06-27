# Climbing Simplified — Game Wiki

A minimalist, physics-based climbing puzzle game built in Godot 4.5. Every move matters — plan your route, manage stamina, and master different climbing disciplines as you scale gym walls, granite cliffs, sandstone towers, ice faces, buildings, and deep-water solo routes. Each hold type behaves differently, weather conditions can turn an easy climb into a serious challenge, and the integrated level editor lets anyone build and share custom routes.

---

## Table of Contents

1. [Game Overview](#game-overview)
2. [Project Map](#project-map)
3. [Collections & Progression](#collections--progression)
4. [Environments](#environments)
5. [Climbing Physics & Character](#climbing-physics--character)
6. [Hold Types](#hold-types)
7. [Hold Modifiers](#hold-modifiers)
8. [Climbing Disciplines](#climbing-disciplines)
9. [Weather System](#weather-system)
10. [Level Data Format](#level-data-format)
11. [Level Editor](#level-editor)
12. [UI & Scene Flow](#ui--scene-flow)
13. [Audio System](#audio-system)
14. [Input & Key Bindings](#input--key-bindings)
15. [Save System](#save-system)
16. [Export & Platforms](#export--platforms)

---

## Game Overview

**Climbing Simplified** simulates realistic climbing challenges: hand fatigue (grip states), body positioning, momentum, limb constraints, and different climbing styles. You control a stick-figure climber with four limbs (two hands, two feet), each independently controllable via keyboard.

The game uses a custom physics simulation (no rigid bodies — it's all hand-rolled spring-and-constraint physics) to create expressive movement that feels like real climbing: dynos, lock-offs, heel hooks, high steps, and cut-loose all emerge naturally from the core system.

### Current Features
- **4 climbing disciplines**: Bouldering, Roped, Speed, Deep Water Solo
- **6 environments**: Gym, Granite, Sandstone, Ice, Building, Deep Water Solo
- **9 hold types**: Start, Top-Out, Jug, Crimp, Sloper, Pocket, Foothold, Undercling, Window (and Ledge)
- **8 weather types**: Rain, Night, Snow, Lightning, Fog, Hail, Sandstorm, and custom time-of-day
- **30+ handcrafted levels** across 5 collections
- **Integrated level editor** with testing, undo, and JSON export
- **Rope system** with animated belayer for roped discipline
- **Speed climbing** with countdown timer
- **Procedural wall rendering** — sky, mountains, clouds, water, all drawn in `_draw()`
- **Persistent menu background** — animated day/night cycle with parallax mountains
- **Full save system** with auto-save on completion
- **Key rebinding** in settings

---

## Project Map

```
res://
├── assets/
│   ├── audio/music/        # 3 music tracks + main menu theme
│   ├── audio/sfx/          # Button click, crashpad, grab-hold, rain SFX
│   ├── images/
│   │   ├── holds/          # Sprites for holds per environment
│   │   │   ├── gym/        # jug, crimp, sloper, pocket, foothold, start, finish
│   │   │   ├── granite/    # granite-crimp, granite-jug, etc.
│   │   │   ├── sandstone/  # sandstone-crimp, sandstone-jug, etc.
│   │   │   ├── building/   # ledge, window
│   │   │   └── ice/        # ice-jug
│   │   ├── identity/       # App icon
│   │   ├── map/            # Collection map icons
│   │   └── popups/         # Tutorial & "topping out" popup images
│   └── textures/           # Cursor, logo SVG, discord icon, lights
├── export/                 # macOS .app, Windows .exe, Web (wasm) builds
├── scenes/
│   ├── editor/
│   │   └── level_editor.tscn      # In-game level editor
│   ├── holds/              # Hold scene files (one per type)
│   │   ├── jug.tscn, crimp.tscn, sloper.tscn, pocket.tscn
│   │   ├── foothold.tscn, start.tscn, top_out.tscn
│   │   ├── ledge.tscn, window.tscn
│   ├── levels/
│   │   ├── tutorial/       # tutorial_01.json — tutorial_10.json (10 levels)
│   │   ├── granite_crag/   # granite_crag_01.json — granite_crag_10.json
│   │   ├── sandstone/      # sandstone_01.json, sandstone_02.json
│   │   ├── building/       # building_01.json, building_02.json
│   │   ├── dws/            # dws_01.json, dws_02.json
│   │   └── ice/            # ice_01.json, ice_02.json
│   ├── main/
│   │   └── main_scene.tscn        # Core gameplay scene
│   ├── menus/
│   │   ├── main_menu.tscn         # Title screen
│   │   ├── collections_select.tscn # Collection/world map
│   │   ├── level_select.tscn      # Level browser with route diagrams
│   │   ├── settings.tscn          # Volume, window, keybinds, reset data
│   │   ├── pause_menu.tscn        # In-game pause overlay
│   │   ├── level_completed.tscn   # Post-climb overlay
│   │   └── fade.tscn              # Cross-scene transition effect
│   ├── player/
│   │   └── character.tscn         # The climber character
│   └── props/
│       └── crashpad.tscn          # Landing crashpad
├── scripts/
│   ├── climbing/
│   │   ├── holds.gd               # ClimbingHold (Area2D) — core hold behavior
│   │   ├── hold_registry.gd       # Autoload — hold discovery & config
│   │   ├── hold_modifiers.gd      # Hold modifier base + FallingHold modifier
│   │   ├── hold_modifier_registry.gd # Autoload — modifier factory
│   │   ├── dynamic_wall.gd        # Procedural wall renderer (sky, mountains, etc.)
│   │   └── wall_holes.gd          # Legacy bolt-hole renderer
│   ├── editor/
│   │   ├── level_editor.gd        # Full level editor (1933 lines)
│   │   ├── level_loader.gd        # Level loading from JSON → scene
│   │   └── editor_state.gd        # Editor state autoload
│   ├── environment/
│   │   ├── environment_config.gd  # Autoload — environment definitions & colors
│   │   ├── weather_modifier.gd    # Particle weather system (rain, snow, etc.)
│   │   ├── menu_background.gd     # Animated cinematic menu background
│   │   └── menu_background_manager.gd # Autoload — persistent background singleton
│   ├── levels/
│   │   ├── main_scene.gd          # Gameplay scene controller (973 lines)
│   │   ├── level_manager.gd       # Level storage & discovery (builtin + user)
│   │   ├── level_loader.gd        # Placeholder (editor variant in scripts/editor/)
│   │   ├── level_transition.gd    # Autoload — scene transition with fade
│   │   └── speed_timer.gd         # Speed climbing countdown timer
│   ├── player/
│   │   ├── character.gd           # The climber — physics, input, visuals (1936 lines)
│   │   ├── climbing_discipline.gd # Discipline enum & display utilities
│   │   └── rope_system.gd         # Top-rope simulation + belayer (741 lines)
│   ├── shaders/
│   │   └── holds-texture.gdshader # Hold outline shader
│   ├── systems/
│   │   ├── game_state.gd          # Autoload — progression, saves, metadata
│   │   ├── music_player.gd        # Autoload — background music playback
│   │   ├── crashpad.gd            # Crashpad landing pad behavior
│   │   ├── custom_cursor.gd       # Autoload — custom mouse cursor
│   │   └── debug.gd               # Diagnostic tool
│   └── ui/
│       ├── transition.gd          # Autoload — scene-to-scene transition manager
│       ├── components/
│       │   ├── buttons.gd         # Button sound effects
│       │   └── fade.gd            # Fade-in/out overlay
│       └── menus/
│           ├── main_menu.gd       # Title screen logic
│           ├── collections_select.gd # Collection selection & lock display
│           ├── level_select.gd    # Level browser with mini route diagrams
│           ├── level_completed.gd # Post-completion overlay
│           ├── pause_menu.gd      # Pause/resume/menu/skip
│           └── settings.gd        # Volume, window, keybinds, reset
├── project.godot
└── export_presets.cfg
```

### Autoloads (Singletons)

| Name | Script | Purpose |
|------|--------|---------|
| `GameState` | `systems/game_state.gd` | Progression, saves, completion tracking |
| `LevelManager` | `levels/level_manager.gd` | Level discovery & metadata |
| `LevelTransition` | `levels/level_transition.gd` | Scene transitions with fade |
| `Transition` | `ui/transition.gd` | Simpler scene-to-scene transitions |
| `EnvironmentConfig` | `environment/environment_config.gd` | Environment definitions & colors |
| `HoldRegistry` | `climbing/hold_registry.gd` | Hold type discovery & behavior config |
| `MusicPlayer` | `systems/music_player.gd` | Background music playback |
| `CustomCursor` | `systems/custom_cursor.gd` | Custom mouse cursor |
| `MenuBackgroundManager` | `environment/menu_background_manager.gd` | Persistent menu background |
| `EditorState` | `editor/editor_state.gd` | Editor state tracking |

---

## Collections & Progression

The game organises levels into **collections** (worlds). Each collection represents a climbing area or style.

### Collections

| ID | Name | Levels | Unlock Requirement |
|----|------|--------|-------------------|
| `intro-gym` | Gym | 10 tutorial climbs | Always unlocked |
| `granite-crag` | Granite Crag | 10 climbs | Complete Gym |
| `sandstone` | Sandstone | 2 climbs | Complete Gym |
| `building` | Building | 2 climbs | Complete Sandstone |
| `deep-water-solo` | Deep Water Solo | 2 climbs | Complete Gym |
| `ice` | Ice | 2 climbs | Complete Gym |

### Level Unlock Rules

- The first **2 levels** in a collection are unlocked as soon as the collection is unlocked
- A level at index `i` unlocks when **either** of the two levels before it (`i-2` or `i-1`) is completed
- This means completing any level always opens up **2 levels ahead**, so players can skip a level they're stuck on
- A `debug_unlock_all` flag exists on GameState to bypass all locks during development

### Progression Tracking

- Each level records your **best completion time** (auto-saved)
- Levels can be **skipped** via the pause menu (after 5+ resets)
- Completed collections get a green checkmark on the collection map
- Progress persists to `user://savegame.json`

---

## Environments

Environments define the visual theme of each level. The `EnvironmentConfig` autoload is the single source of truth — adding a new environment means adding one entry to its `ENVIRONMENTS` dict.

### Available Environments

| Type | Wall Color | Background Color | Bolt Holes | Sprite Suffix |
|------|-----------|-----------------|------------|---------------|
| GYM | Tan (#D1BF9E) | Sky blue (#87CFEB) | Yes | Gym |
| GRANITE | Grey (#9B9BA7) | Sky blue (#87CFEB) | No | Granite |
| SANDSTONE | Sandy brown (#C29A6B) | Sandy yellow (#D9BF8C) | No | Sandstone |
| BUILDING | Grey (#85858A) | Blue (#295CB3) | No | Building |
| ICE | Pale glacial blue (#B8E0F5) | Pale blue (#9ECCEB) | No | Ice |
| DEEP_WATER_SOLO | Same as granite | Deep blue (#2E6BB8) | No | Granite |
| MENU_SUNSET | Muted purple (#8C7A9E) | Pink (#ECA6C7) | No | Granite |

### How Environments Work

1. Each hold scene has **sprite variants** named with the environment suffix (e.g. `JugGym`, `JugGranite`)
2. When a level loads, `EnvironmentConfig.set_environment()` is called
3. All holds swap their visible sprite to match the environment
4. The `DynamicWall` updates its wall color, background, and bolt-hole rendering
5. Crashpads also swap sprites per environment

---

## Climbing Physics & Character

### Node Structure

The character (`character.tscn`) is a `CharacterBody2D` with this limb layout:

```
Character (CharacterBody2D)
├── LeftHand (Node2D)
│   ├── Sprite2D (hidden, used for visual dot)
│   ├── Area2D (collision detection for grab)
│   └── Marker2D
├── RightHand (same structure)
├── LeftFoot (same structure)
├── RightFoot (same structure)
├── LeftHandJoint (Node2D) — elbow position
├── RightHandJoint — elbow position
├── LeftFootJoint — knee position
├── RightFootJoint — knee position
├── BodySprite (hidden)
├── CollisionShape2D (body collision)
├── SpotLight2D (headlamp for night)
└── ColorRect (darkness overlay)
```

The character is entirely **drawn with code** in `_draw()` — no sprite textures. It renders as a stick figure with colored dots for hands/feet, lines for limbs, and visual feedback for grip states.

### Limb State System

Each limb is tracked by a `LimbState` object (inner class in `character.gd`):

| Property | Description |
|----------|-------------|
| `hold` | Reference to the Area2D hold the limb is grabbing |
| `pin` | World-space snap position on the hold |
| `anchor` | The hold's attractor point |
| `pressure` | Current grip pressure (0-100+) |
| `grip` | GripState enum (RELAXED, ENGAGED, PUMPED, FAIL) |
| `velocity` | Limb velocity vector |
| `is_grabbing` | Whether the limb is mid-grab animation |
| `selected` | Whether the player has selected this limb |
| `shake_offset` | Visual shake offset (increases with pressure) |

**HandState** extends `LimbState` with `fail_stage`, `struggle_timer`, and `catch_boost`.

**FootState** extends `LimbState` with `manual` and `user_override` flags.

### Grip State System

Grip states track hand fatigue independently for each hand:

| State | Pressure Range | Reach Mult | Speed Mult | Shake | Description |
|-------|---------------|------------|------------|-------|-------------|
| RELAXED | 0 – 24.9 | 1.0× | 1.0× | None | No strain |
| ENGAGED | 25 – 59.9 | 0.9× | 0.95× | 10% | Moderate strain |
| PUMPED | 60 – 99.9 | 0.75× | 0.7× | 35% | High strain, reduced performance |
| FAIL | 100+ | 0.0× | 0.0× | 100% | Failure, auto-releases limb |

**Pressure Tracking**:
- Increases with hold difficulty, body offset from ideal position, and static time
- Decreases with recovery (rest value of hold) and when the limb is free
- Multiplied by load distribution (fewer held limbs = more pressure per limb)

### Physics Simulation

The core `simulate_physics()` runs every frame and includes:

1. **Gravity**: 2200 px/s² — reduced when hands are holding
2. **Joint constraints**: 2-bone IK with 5 iterations — enforces arm/leg lengths
3. **Body pulling**: The body is pulled toward held limbs (weighted by load distribution)
4. **Foot support**: Feet provide vertical lift and lateral centering
5. **Adaptive legs**: Auto-push on extended reaches
6. **Hip shift**: Mouse-driven weight shifting for dynamic movement
7. **Drag**: Body (0.96) and limb (0.94) velocity damping
8. **No upside-down enforcement**: Feet must stay below hands
9. **Overload release**: Limbs auto-release if stretched beyond tolerance
10. **Crossing prevention**: Arms and feet can't cross (configurable)

### Input Controls

| Key | Action |
|-----|--------|
| **Q** | Select/release left hand |
| **E** | Select/release right hand |
| **A** | Select/release left foot |
| **D** | Select/release right foot |
| **Mouse** | Aim selected limb toward cursor |
| **Shift** | Hold for rest mode (shake out) |
| **Shift + select** | Quick-tap: release a held limb |
| **ESC / R** | Reset climb |

When a limb is selected, moving the mouse aims it toward the cursor. Releasing the key (or clicking) attempts to grab the nearest valid hold.

### Rest Mode

Hold Shift with no limb selected and at least one hand on a hold to enter **rest mode**. This lets you shake out on jugs and recover pressure faster. The recovery rate while shaking out is 14.0 pressure/second.

### Fall & Ragdoll

- Fall detection triggers after 2 seconds with velocity > 400 px/s with no hand holds
- The rope system catches falls in Roped discipline
- Without a rope, the climber ragdolls for 2 seconds then resets
- Crashpads soften landings in bouldering

### Visual Feedback

The climber's appearance changes dynamically:
- **Hand/foot dots** change color based on grip state (green → yellow → red → white/purple)
- **Shake** amplitude increases with pressure
- **Scale** of free limbs grows slightly while searching
- **Dark overlay** and vignette intensify as pressure increases (P2 fatigue system)
- A **shadow** of the climber is drawn on the wall surface

### Key Physics Constants

| Constant | Value | Description |
|----------|-------|-------------|
| ARM_UPPER_LENGTH | 50.0 | Upper arm length (px) |
| ARM_LOWER_LENGTH | 50.0 | Lower arm length |
| LEG_UPPER_LENGTH | 45.0 | Upper leg length |
| LEG_LOWER_LENGTH | 45.0 | Lower leg length |
| GRAVITY | 2200.0 | Gravity acceleration |
| BODY_PULL_STRENGTH | 0.55 | Pull toward held limbs |
| JOINT_STIFFNESS | 0.92 | Joint constraint stiffness |
| FOOT_SUPPORT_STRENGTH | 0.40 | Vertical foot push force |
| HAND_LOAD_TOLERANCE | 1.08 | Max arm stretch before release |
| FOOT_RELEASE_THRESHOLD | 2.2 | Max leg stretch before release |
| FOOT_CUT_THRESHOLD | 320.0 | Lateral velocity to cut feet |

---

## Hold Types

Holds are `Area2D` nodes with the `ClimbingHold` script (class_name). They are auto-discovered by `HoldRegistry` and configured centrally in `HOLD_CONFIGS`.

### Hold Type Reference

| Type | Difficulty | Rest Value | Snaps? | Max Limbs | Special |
|------|-----------|------------|--------|-----------|---------|
| **START** | 0.0 | 50.0 | Yes | 2 | Starting position marker |
| **TOP** (Top Out) | 0.0 | 100.0 | Yes | 2 | Finish hold — both hands on = completion |
| **JUG** | 0.0 | 50.0 | Yes | 2 | Big, easy hold, great for resting |
| **CRIMP** | 3.0 | 0.0 | No | 2 | Tiny edge — high difficulty, no rest |
| **SLOPER** | 2.5 | 0.0 | No | 2 | Rounded — drains pressure continuously |
| **POCKET** | 1.2 | 0.0 | Yes | **1** | One-finger pocket — one limb only |
| **FOOTHOLD** | 1.0 | 0.0 | Yes | 2 | Feet-only — hands can't grab |
| **WINDOW** | 1.5 | 5.0 | No | 4 | Building-specific, snap disabled, free placement |
| **LEDGE** | N/A | N/A | N/A | N/A | Building ledge decoration |
| **UNDERCLING** | 2.2 | 0.0 | Yes | 2 | Snaps, moderate difficulty |
| **PINCH** | 2.0 | 0.0 | No | 2 | Pinch grip, no snap |

Key behaviors:
- **Crimps** and **Slopers** don't snap — limbs land where the player aims, increasing precision requirements
- **Pockets** lock to one limb — if occupied, other limbs can't grab it
- **Footholds** reject hands (only feet can grab them)
- **Windows** allow up to 4 limbs and have no snap — each hand grabs its own spot
- **Slopers** apply continuous pressure drain (the `sloper_drain` flag)

---

## Hold Modifiers

The `HoldModifierBase` class allows adding dynamic behavior to holds. Modifiers are instantiated at placement time in the level editor and saved to the level JSON.

### FallingHold

A hold that shakes when grabbed, then falls apart after a few seconds. Uses a state machine:

1. **IDLE** — normal
2. **WARN** — starts shaking when grabbed
3. **FALLING** — falls after shake duration
4. **GONE** — hold disappears

This forces the player to move quickly off precarious holds.

### How to Add a New Modifier

1. Create a new inner class in `hold_modifiers.gd` extending `HoldModifierBase`
2. Register it in `hold_modifier_registry.gd::create_modifier()`
3. Add a display name to `MODIFIER_DISPLAY_NAMES`

---

## Climbing Disciplines

The game supports three distinct climbing styles, defined in `ClimbingDiscipline`:

### Bouldering
- No rope, no timer
- Complete by getting both hands on the top-out hold
- Crashpads provide safe landings
- Falling = ragdoll then reset

### Roped (Top-Rope)
- A rope is attached with an animated belayer at the bottom
- The rope system catches falls with a realistic catch deceleration
- After a catch, the belayer slowly lowers the climber
- The belayer is a fully animated stick figure with reactive animation

### Rope System Details (`rope_system.gd`)

The rope is simulated as 28 connected segments with spring physics. The belayer is drawn as a stick figure with reactive animations:

- **Breathing / swaying** idly
- **Alertness** increases as the climber's velocity spikes
- **Brace** — feet spread and body leans when tension builds
- **Catch** — a sharp pull then controlled lower on fall catch
- **Slack bursts** — the belayer rhythmically takes in rope
- **Head tracking** — the belayer looks up at the climber

The catch state machine has 4 states: IDLE → FALLING (short drop) → STRETCHING (rope catches) → HELD (lowering to ground).

### Speed Climbing
- A countdown timer (default 60s) starts when the climber first moves
- Timer counts down with color feedback: white → amber at 10s → red at 5s
- Complete by reaching the top-out before time expires
- The `SpeedTimer` node emits signals for expiry and warnings

### Deep Water Solo
- No rope, no crashpads — falling means hitting water below
- The `DynamicWall` renders water and splash effects
- Just place the wall over water and set the environment

---

## Weather System

The `WeatherModifier` class provides an **entirely code-drawn** particle weather system — no GPU particles, no sprite nodes. Everything is rendered in `_draw()` with `draw_*` calls.

### Weather Types

| Type | Key Features |
|------|-------------|
| NONE | Clear skies |
| RAIN | 180 falling streaks, splashes on surfaces, wind-affected, dark sky |
| NIGHT | Darkness overlay (0.94 alpha), headlamp, ambient light, dark sky |
| SNOW | 200 drifting flakes with sway, accumulation on surfaces, fog |
| LIGHTNING | Random bolts with branches, flash, glow, heavy rain + thunder audio |
| FOG | 6 scrolling layers at different heights/opacities, ground fog band |
| HAIL | 120 falling hailstones that bounce on impact |
| SANDSTORM | 250 horizontal sand streaks, amber haze overlay, dense ground dust |

Each weather type also defines its own sky colors, cloud colors, and fog colors for a fully coherent look. Weather blends smoothly when toggling (1.2s blend speed).

Weather can be set per-level in the level JSON and adjusted in the level editor.

### Dynamic Wall

The `DynamicWall` (2260 lines) is the procedural backdrop that handles:
- **Sky gradient** (custom per environment/weather)
- **Mountains** — procedurally generated silhouettes from seed
- **Clouds** — multi-layer, scrolling at different speeds
- **Ground** — with optional water rendering
- **Wall surface** — the climbing wall polygon with texture variation
- **Bolt holes** — grid of small dots for gym environments
- **Water** — animated with splash effects on player entry
- **Outline** — wall edge outline matching the character's style

The wall redraws at 12-30 fps (lower when nothing is moving) to save performance.

---

## Level Data Format

Levels are stored as **JSON files** with the following structure:

```json
{
  "name": "Ladder",
  "grade": "VB",
  "environment": "gym",
  "discipline": "bouldering",
  "speed_time_limit": 60.0,
  "weather": 0,
  "weather_intensity": 1.0,
  "time_of_day": 0.5,
  "belayer_position": { "x": -150, "y": 200 },
  "holds": [
	{ "type": "START", "x": 32.0, "y": 0.0 },
	{ "type": "JUG",   "x": -32.0, "y": -96.0, "modifiers": ["falling"] },
	{ "type": "TOP",   "x": 0.0, "y": -448.0 }
  ],
  "crashpads": [
	{ "x": 0.0, "y": 192.0 },
	{ "x": -224.0, "y": 192.0 }
  ],
  "wall_polygon": {
	"enabled": true,
	"points": [
	  { "x": -222.99, "y": -545.92 },
	  { "x": 237.93, "y": -544.16 },
	  { "x": 244.59, "y": 214.0 },
	  { "x": -215.29, "y": 214.0 }
	],
	"ground_left_index": 3,
	"ground_right_index": 2,
	"top_edge_indices": []
  }
}
```

### Field Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | String | "" | Climb name |
| `grade` | String | "" | V-scale (VB-V12) or YDS (5.5-5.13) |
| `environment` | String | "gym" | gym, granite, sandstone, building, ice |
| `discipline` | String | "bouldering" | bouldering, roped, speed |
| `speed_time_limit` | Float | 60.0 | Countdown in seconds for speed climbing |
| `weather` | Int | 0 | 0=None, 1=Rain, 2=Night, 3=Snow, 4=Lightning, 5=Fog, 6=Hail, 7=Sandstorm |
| `weather_intensity` | Float | 1.0 | Weather effect strength |
| `time_of_day` | Float | 0.5 | 0=midnight, 0.5=noon (affects MenuBackground only) |
| `belayer_position` | Dict | null | World position of the belayer for roped climbing |
| `holds` | Array | [] | Array of hold descriptors |
| `holds[].type` | String | "JUG" | START, TOP, JUG, CRIMP, SLOPER, POCKET, FOOT, WINDOW, LEDGE |
| `holds[].x` | Float | 0 | World position X |
| `holds[].y` | Float | 0 | World position Y |
| `holds[].modifiers` | Array | [] | Modifier type keys (e.g. ["falling"]) |
| `holds[].custom_spawn` | Bool | false | If true, player spawns at this hold |
| `crashpads` | Array | [] | Crashpad positions {x, y} |
| `wall_polygon` | Dict | null | Custom wall shape polygon |

---

## Level Editor

The integrated level editor (`scenes/editor/level_editor.tscn`, script `level_editor.gd`, ~1933 lines) lets you build and test climbing routes entirely within the game.

### UI Layout

```
┌────────────────────────────────────────────────────────────┐
│ [Route Name] [Grade ▼] [Discipline ▼] [Test] [Save] [...] │ ← Top Bar
├──────┬─────────────────────────────────────────────────────┤
│      │                                                     │
│ PAL  │              CLIMBING WALL                         │
│ ETTE │              (canvas)                              │
│      │                                                     │
│ JUG  │        [hold]    [hold]                             │
│ CRMP │             [hold]                                  │
│ SLPR │        [hold]    [hold]    [hold]                   │
│ POCK │                                                     │
│ FOOT │    (right-click hold → properties panel)            │
│ WIND │                                                     │
│ LEDG │                                                     │
│      │                                                     │
├──────┴─────────────────────────────────────────────────────┤
│ [Weather ▼] [Intensity ═══] [Collapse ▲]                  │ ← Drawer
└────────────────────────────────────────────────────────────┘
```

### Features
- **Palette**: Click a hold type, then click on the wall to place it
- **Drag & drop**: Move placed holds by dragging
- **Right-click**: Context properties panel for each hold
- **Undo**: Full undo stack for placement/deletion
- **Wall polygon editor**: Click to add/remove vertex points
- **Test mode**: Press "Test" to load the route and try climbing it
- **Weather controls**: Select weather, adjust intensity
- **Discipline extras**: Speed timer limit, belayer placement
- **Rope visual**: During test mode in roped discipline, a rope line is drawn
- **Hold outline shader**: Modified holds get a colored outline via shader
- **Wall-type filtering**: Holds like Window only appear when environment is "building"
- **Grid snap**: Toggle grid with configurable size
- **Save/Load**: Saves to JSON format, reloads from saved file
- **Crashpads**: Place landing pads for bouldering routes

### Editor Shortcuts

| Input | Action |
|-------|--------|
| Click hold type | Select hold to place |
| Click on canvas | Place hold |
| Drag hold | Move it |
| Right-click hold | Open properties |
| Scroll | Zoom in/out |
| Middle-click drag | Pan canvas |
| Delete key | Remove selected hold |
| Ctrl+Z | Undo |

---

## UI & Scene Flow

### Navigation Flow

```
Main Menu
  ├── Play → Collections Select → Level Select → Game Scene (load JSON)
  │                                                ├── Pause Menu
  │                                                ├── Level Completed Overlay
  │                                                └── Next / Restart / Menu
  ├── Level Maker → Level Editor
  │                ├── Test (loads current route)
  │                └── Save JSON
  ├── Settings → Volume, Window Mode, VSync, FPS Cap, Keybinds, Reset Data
  └── Quit
```

### Scene Transitions

All scene changes use the `Transition` autoload (or `LevelTransition` for gameplay), which:
1. Fades the screen to black using the `Fade` scene
2. Loads the new scene
3. Fades back in

For gameplay transitions, `LevelTransition` also handles loading the level JSON, spawning holds, positioning the player, and validating the level before showing the scene.

### Route Preview

When entering a level, the camera first zooms out to show the **full route**, giving the player a chance to plan their moves. After a 5-second hold at the overview, it zooms back into the player. Players can also press Tab to toggle the route view at any time.

### Level Select Route Diagrams

The level select screen renders a **mini diagram** of each route:
- Hold types shown as colored dots at their world positions
- Colors correspond to hold types (green=start, blue=top, orange=crimp, etc.)
- Locked routes show a greyed-out diagram with a lock overlay
- Tags show discipline, environment, weather, and time-of-day
- Stats show completion status, best time, hold count, and crashpad count

### Popup System

First-time players see tutorial popups with helpful images:
- **Tutorial popup** — appears on first launch, explains controls
- **Topping out popup** — appears on first granite level, explains the finish mechanic
- Popups are tracked in `user://prefs.cfg` so they only show once

### Menus

All menu scenes call `MenuBackgroundManager.show()` in their `_ready()` to display the shared animated cinematic background (day/night cycle with parallax mountains, sunset menu theme).

The settings menu supports:
- Master volume slider
- Window mode (Windowed/Fullscreen/Exclusive)
- VSync toggle
- FPS cap (Unlimited/60/120/144)
- **Key rebinding** — click a keybind button, press a key to rebind
- **Reset all progress** — with confirmation dialog

The pause menu supports:
- Resume
- Settings
- Skip Level (appears after repeated resets on difficult climbs)
- Main Menu

---

## Audio System

### Music Player (`MusicPlayer` autoload)

- Plays from 3 tracks (`Track_1.mp3`, `Track_2.mp3`, `Track_3.mp3`)
- Uses history tracking to avoid repeating the same track
- Random silence gaps (5-30s) between tracks for natural feel
- Separate bus named "Music" for volume control
- Main Menu has its own theme (`Main_Menu_Theme.m4a`)

### SFX

| Sound | File | Trigger |
|-------|------|---------|
| Button click | `button-clicked.wav` | Any menu button press |
| Grab hold | `grab-hold.wav` | When a limb grabs a hold |
| Crashpad landing | `crashpad.wav` | Landing on a crashpad |
| Rain ambience | `rain_sfx.wav` | Looped during rain/lightning weather |

---

## Input & Key Bindings

### Default Key Map

| Action | Default Key | Input Map Name |
|--------|------------|----------------|
| Select left hand | **Q** | `select_left` |
| Select right hand | **E** | `select_right` |
| Select left foot | **A** | `select_left_foot` |
| Select right foot | **D** | `select_right_foot` |
| Rest mode | **Shift** (hold) | — |
| Reset | **R** or **ESC** | `ui_cancel` |
| Pause | **ESC** | `ui_cancel` |
| Route overview | **Tab** | — (handled in main_scene) |

All four limb selection actions are rebindable in the Settings menu. Keybinds persist to `user://settings.cfg`.

### Gameplay Controls

- **Select a limb** → press its key. The limb becomes mouse-controlled.
- **Release to grab** → releasing the key (or pressing it again quickly) attempts to grab the nearest valid hold.
- **Quick-tap** → press and release quickly (<0.1s) to release a held limb without aiming.
- **Shift+select** → press a limb's key while holding Shift to release it (e.g. to cut feet loose).
- **Rest mode** → hold Shift with no limb selected and at least one hand on a hold.
- **Aim** → while a limb is selected, move the mouse toward the target hold.

---

## Save System

### Game Progress (`user://savegame.json`)

Auto-saved on:
- Level completion (records best time)
- Level skip
- Collection completion

Stores:
- `completed_levels` — map of level_path → best_time (or -1 for skipped)
- `completed_collections` — array of completed collection IDs
- `climb_metadata` — climb names and grades per level path
- `current_level` / `current_collection` — last played state

### Settings (`user://settings.cfg`)

Manually saved via Settings → Save button. Stores:
- Master volume (dB)
- Window mode index
- VSync toggle
- FPS cap index
- Keybindings (physical keycode per action)

### Popup Preferences (`user://prefs.cfg`)

Tracks which tutorial popups have been seen so they don't replay. Also tracks instruction dismissal.

---

## Export & Platforms

Export presets are configured for three platforms:

| Platform | Output |
|----------|--------|
| macOS | `.app` bundle inside `.dmg` |
| Windows | `.exe` |
| Web | HTML5 with `.wasm` + `.pck` |

The `export/` directory contains pre-built binaries for all three platforms. The game uses Godot 4.5's Forward Plus renderer with MSAA 2x.

---

## Development

### Adding a New Hold Type

1. Add an asset sprite to `assets/images/holds/<environment>/`
2. Create a scene file in `scenes/holds/` (e.g. `pinch.tscn`)
3. Register it in `hold_registry.gd::_register_all_holds()` and add its config to `HOLD_CONFIGS`
4. That's it! The editor palette and level loader pick it up automatically.

### Adding a New Environment

1. Add your type to `EnvironmentType` enum in `environment_config.gd`
2. Add its config (colors, sprite suffix) to the `ENVIRONMENTS` dict
3. Create hold sprites with the matching suffix (e.g. `JugMyEnvironment`)
4. Add an `ENV_COLORS` entry in `level_select.gd` for the route diagram

### Adding a New Weather Type

1. Add your type to `WeatherType` enum in `weather_modifier.gd`
2. Add all visual parameters (colors, densities, speeds)
3. Implement the `_draw_*` function for your weather particles
4. Add it to the editor's `WEATHER_NAMES` array and the `WEATHER_NAMES` dict in `level_select.gd`

### Adding a New Modifier

1. Create a new inner class in `hold_modifiers.gd` extending `HoldModifierBase`
2. Register it in `hold_modifier_registry.gd::create_modifier()`
3. Add a display name to `MODIFIER_DISPLAY_NAMES`

### Architecture Principles

- **Hold behavior** is defined centrally in `HoldRegistry.HOLD_CONFIGS` — not scattered across scenes
- **Environment data** is defined centrally in `EnvironmentConfig.ENVIRONMENTS`
- **All drawing is procedural** — the character, wall, weather, and menu background are all code-drawn with `_draw()`
- **Levels are data-driven** — JSON files with no scene dependencies
- **Autoloads handle cross-cutting concerns** — progression, audio, transitions, environment, holds
- **Adding new content** rarely requires touching gameplay code — just config, assets, and scenes
