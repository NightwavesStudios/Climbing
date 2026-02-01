# Climbing Game Mechanics and Systems

## Overview

This README summarizes the mechanics and systems of a 2D climbing game built in Godot. The game features physics-based climbing with expressive grip states, limb management, adaptive foot placement, and contextual difficulty. The core script extends `CharacterBody2D` for the climber, while holds are managed via a `ClimbingHold` class extending `Area2D`.

The game simulates realistic climbing challenges like hand fatigue (grip states), body positioning, momentum, and limb constraints. It supports mouse-controlled limb movement, auto foot placement, and visual feedback.

## Node Structure

Key child nodes for limbs, joints, and camera:

| Node              | Description                          |
|-------------------|--------------------------------------|
| `left_hand`       | Left hand position (Node2D).         |
| `right_hand`      | Right hand position (Node2D).        |
| `left_foot`       | Left foot position (Node2D).         |
| `right_foot`      | Right foot position (Node2D).        |
| `left_hand_joint` | Left elbow joint (Node2D).           |
| `right_hand_joint`| Right elbow joint (Node2D).          |
| `left_foot_joint` | Left knee joint (Node2D).            |
| `right_foot_joint`| Right knee joint (Node2D).           |
| `left_hand_area`  | Left hand collision area (Area2D).   |
| `right_hand_area` | Right hand collision area (Area2D).  |
| `left_foot_area`  | Left foot collision area (Area2D).   |
| `right_foot_area` | Right foot collision area (Area2D).  |
| `cam`             | Camera for following the climber (Camera2D, with lerp smoothing at 0.08). |

## Visual Toggles

| Toggle     | Type | Default | Description |
|------------|------|---------|-------------|
| `debug`    | bool | false   | Enables debug visuals (e.g., COM dot, velocity arrows). |
| `aesthetic`| bool | true    | Enables aesthetic visuals (e.g., stick figure, colored hand/foot dots based on state). |

## Grip State System

Grip states track hand fatigue independently for each hand, affecting movement and visuals.

### Grip States

| State     | Description               | Pressure Threshold |
|-----------|---------------------------|--------------------|
| RELAXED   | No strain.                | 0 - 24.9           |
| ENGAGED   | Moderate strain.          | 25 - 59.9          |
| PUMPED    | High strain, reduced performance. | 60 - 99.9 |
| FAIL      | Failure, auto-releases limb. | 100+          |

- **Pressure Tracking**: 0-100 float per hand; increases with hold difficulty, body offset, and static time; decreases with recovery or when free.
- **Update Logic**: In `_process`; calculates net change based on hold pressure minus recovery.
- **Body Factors**:
  - Offset: Distance from ideal position (normalized 0-1).
  - Balance: Score from held limbs (hands/feet) + low velocity (0-1).
- **Visuals**: Shake effects increase with strain.

### Movement Modifiers by Grip State

| State     | Reach Mult | Speed Mult | Latency | Shake |
|-----------|------------|------------|---------|-------|
| RELAXED   | 1.0        | 1.0        | 0.0     | 0.0   |
| ENGAGED   | 0.9        | 0.95       | 0.05    | 0.1   |
| PUMPED    | 0.75       | 0.7        | 0.15    | 0.35  |
| FAIL      | 0.0        | 0.0        | 1.0     | 1.0   |

## Limb Management

### Limb Enum

| Limb         | Description |
|--------------|-------------|
| NONE         | No selection. |
| LEFT_HAND    | Left hand.  |
| RIGHT_HAND   | Right hand. |
| LEFT_FOOT    | Left foot.  |
| RIGHT_FOOT   | Right foot. |

- **Selection**: Via input; releases if held.
- **Holds**: References to `Area2D` holds; anchors for snap positions.
- **Grab Animations**: Lerp to target at speed 1.0.
- **Foot Flags**: Manual placement, auto-disable.

## Physics Constants

### Body and Limb Dimensions

| Constant            | Value | Description |
|---------------------|-------|-------------|
| ARM_UPPER_LENGTH    | 45.0  | Upper arm length. |
| ARM_LOWER_LENGTH    | 45.0  | Lower arm length. |
| LEG_UPPER_LENGTH    | 40.0  | Upper leg length. |
| LEG_LOWER_LENGTH    | 40.0  | Lower leg length. |
| SHOULDER_OFFSET     | 10.0  | Horizontal shoulder offset. |
| HIP_OFFSET          | 10.0  | Horizontal hip offset. |
| HIP_DOWN            | 20.0  | Vertical hip offset. |
| HEAD_OFFSET         | -20.0 | Vertical head offset. |

### Forces and Behaviors

| Constant                  | Value | Description |
|---------------------------|-------|-------------|
| BODY_PULL_STRENGTH        | 0.25  | Pull toward held limbs. |
| JOINT_STIFFNESS           | 0.98  | Joint constraint stiffness. |
| LIMB_STIFFNESS            | 0.98  | Limb constraint stiffness. |
| FOOT_SUPPORT_STRENGTH     | 0.15  | Vertical foot push. |
| FOOT_SUPPORT_MIN_Y        | -20.0 | Min relative Y for support. |
| FOOT_SUPPORT_MAX_PUSH     | 50.0  | Max push distance. |
| FOOT_LATERAL_ASSIST       | 0.08  | Lateral centering from feet. |
| GRAVITY                   | 2400.0| Gravity (reduced with hands). |
| BODY_DRAG                 | 0.88  | Body velocity drag. |
| LIMB_DRAG                 | 0.85  | Limb velocity drag. |
| MAX_JOINT_STRETCH         | 1.08  | Max joint extension. |
| MAX_LIMB_STRETCH          | 1.08  | Max limb extension. |
| PREVENT_UPSIDE_DOWN       | true  | Feet below hands. |
| COM_OFFSET_Y              | 15.0  | Center of Mass offset. |
| FOOT_CUT_THRESHOLD        | 150.0 | Lateral cut velocity. |
| HAND_LOAD_TOLERANCE       | 1.35  | Max arm stretch. |
| MOMENTUM_TRANSFER_STRENGTH| 0.4   | Limb to body momentum. |
| DYNO_VELOCITY_BOOST       | 1.2   | Dynamic move boost. |
| ARM_NATURAL_ANGLE         | 25.0  | Natural arm hang angle (degrees). |
| ARM_NATURAL_BEND          | 0.7   | Natural arm bend multiplier. |
| LEG_NATURAL_SPLAY         | 15.0  | Natural leg splay (unused). |
| FREE_LIMB_RELAXATION_SPEED| 0.15  | Natural position lerp. |

### Adaptive and Auto Features

| Constant                | Value | Description |
|-------------------------|-------|-------------|
| ENABLE_ADAPTIVE_LEGS    | true  | Leg push on reaches. |
| LEG_ASSIST_THRESHOLD    | 0.8   | Reach ratio trigger. |
| LEG_ASSIST_STRENGTH     | 0.6   | Assist force multiplier. |
| LEG_ASSIST_SPEED        | 0.3   | Assist speed. |
| LEG_ASSIST_MAX_EXTENSION| 0.92  | Max leg extension for assist. |
| AUTO_FOOT_PLACEMENT     | true  | Auto place feet. |
| FOOT_SEARCH_RADIUS      | 80.0  | Search radius for auto placement. |
| FOOT_PLACEMENT_TIMER    | 0.5   | Cooldown between placements. |
| FOOT_PREFERENCE_BELOW   | 40.0  | Bonus score for below-body holds. |
| FOOT_RELEASE_THRESHOLD  | 1.35  | Max leg stretch before release. |
| CRIMP_LEG_SPEED_FACTOR  | 0.45  | Foot speed reduction on crimps. |

### Movement Constants

| Constant              | Value | Description |
|-----------------------|-------|-------------|
| MOUSE_CONTROL_ENABLED | true  | Enables mouse aiming. |
| MOUSE_DEADZONE        | 5.0   | Min distance to aim. |
| ALLOW_ARM_CROSSING    | false | Prevents arm crossing. |
| ALLOW_FOOT_CROSSING   | false | Prevents foot crossing. |
| MIN_HAND_SEPARATION   | 20.0  | Min hand separation. |
| MIN_FOOT_SEPARATION   | 15.0  | Min foot separation. |
| LIMB_GRAB_SPEED       | 1.0   | Grab animation lerp speed. |
| BASE_HAND_MOVE_SPEED  | 0.85  | Base limb move speed. |
| BASE_REACH_DISTANCE   | 200.0 | Base reach (unused). |
| BASE_INPUT_LATENCY    | 0.0   | Base latency (unused). |
| BASE_SHAKE            | 0.0   | Base shake (unused). |

## Physics Simulation

Core logic in `simulate_physics` (called in `_process`):

- Counts held limbs; adds momentum if reduced.
- Applies gravity (full fall if no hands, cuts feet).
- Pins held limbs to anchors.
- Applies gravity to free limbs.
- Handles mouse control for selected limb (with modifiers, limits).
- Lerps free arms to natural hang.
- Adaptive legs: Pushes body on extended reaches.
- Foot support: Vertical/lateral forces.
- Cuts feet on high lateral velocity.
- Pulls body toward held limbs (weighted).
- Updates COM position.
- Applies limb velocities.
- Enforces no upside-down.
- Checks overload releases.
- Applies joint constraints (5 iterations, 2-bone IK).
- Updates grab animations.
- Re-pins holds.
- Prevents crossing.
- Applies drag.

## Auto Foot Placement

- Cooldown timer (0.5s).
- Releases auto feet if no hands.
- Searches radius (80px) for best hold (scoring: distance, below-body, side, type bonus).
- Filters: Not occupied, below body/hands, reachable, no crossing.
- Snaps if claimable.

## Initial Grab and Climb Logic

- Finds start holds or nearest.
- Snaps hands/feet accordingly.
- Climb starts on first grab; completes if both hands on top-out.

## Input Handling

- Reset on ESC/R.
- Select/release limbs (attempt grab on release).
- Mouse aiming if selected and > deadzone.

## Climbing Hold Types

| HoldType  | Description          | Difficulty | Rest Value |
|-----------|----------------------|------------|------------|
| JUG       | Easy, good rest.     | 0.0        | 2.0        |
| START     | Starting hold.       | 0.0        | 2.5        |
| TOP_OUT   | Finishing hold.      | 0.0        | 3.0        |
| CRIMP     | Small, straining.    | 1.5        | 0.0        |
| SLOPER    | Rounded, slippery.   | 3.0        | 0.0        |
| FOOTHOLD  | Foot-specific.       | 0.0        | 0.5        |
| POCKET    | One-limb only.       | 1.0        | 0.0        |

- **Properties**: Difficulty (pressure/s), rest value (recovery/s).
- **Occupation**: Pockets one-limb; footholds feet-only.
- **Pressure Calculation**: Base + sloper bonus + offset + static.
- **Recovery**: Base + balance bonus if >0.
