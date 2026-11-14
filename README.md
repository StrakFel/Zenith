# ZENITH

Educational 2D space-mission game for the **NASA Space Mission Design Game Hackathon**.
Godot 4.7 (GL Compatibility), GDScript only, all art is drawn procedurally (no external assets).

## Missions

| # | Mission | Status |
|---|---------|--------|
| 1 | Rocket Assembly & Launch - drag-and-drop build (mass, fuel, thrust, TWR, delta-v, cost), countdown, gravity-turn flight with Max-Q, orbit insertion, satellite deployment | playable |
| 2 | Spacewalk - zero-g inertia, limited thruster gas and oxygen, repair a satellite, return to the airlock slowly | prototype (playable) |
| 3 | ISS Docking - RCS translation + rotation, approach corridor, tolerance indicators, hard-dock check | prototype (playable) |
| 4-5 | locked placeholders | registered in `Core/mission_registry.gd` |

## Project layout

```
Core/            autoloads (Loc, GameState, Router), UI kit, translations, units
Core3D/          3D toolkit: SpaceStage (sky/sun/Earth/clouds), Rocket3D, LaunchPad3D, PadScene3D,
				 FlightDirector3D (cameras + FX), RingMarker3D, Fx3D, shaders/ (procedural, no textures)
Assets/Models/   .glb models generated from Blender (rocket parts, launchpad, station, ship, ...)
Menus/TempMenu/  TEMPORARY 3D main menu / mission select / settings  (GameMenu/ is left untouched)
Missions/Shared/ MissionBase, briefing, pause, result screen, off-screen arrow
Missions/MissionN/  one folder per mission: gameplay simulation (reused) + 3D view
Legacy2D/        the old 2D renderers (kept for reference, no longer used)
Tools/           headless balance sim, end-to-end autopilot tests, screenshots, Blender/ asset generator
```

## Science loop (NASA-style)
Mission 1 follows *Scientific goal -> Requirements -> Mission design -> Verification -> Launch -> Science results*
and models the four segments: **Launch** (rocket), **Space** (satellite power/battery/orbit), **Ground**
(downlink in one contact window per orbit) and **Users** (what the data is worth). The maths lives in
`Missions/Mission1/m1_design.gd` (goals, instruments, solar/battery/antenna, requirements, science result) and is
deliberately simplified (fixed eclipse and contact time, no orbit decay, linear altitude-window penalty) - it teaches
trade-offs, it is not GMAT-grade analysis. Mission 2 ties repairs to the satellite's science output, Mission 3 delivers a
fragile experiment (gentle docking = better data).

## Menus and camera
* **Play** launches the next available mission straight away (Mission 1 with no progress; the last mission when
  everything is done). **Missions** opens the 3D mission map: previews, description, difficulty, progress.
  Missions unlock one after another, completed ones can be replayed, 4-5 are "coming soon".
* `Core3D/orbit_camera_controller.gd` (`OrbitCameraController`) - reusable Mission-Viz style camera:
  LMB drag rotate 360 deg (with inertia), wheel zoom (clamped), RMB drag pan, **R** reset, double-click focus.
  It keeps the camera out of models (sphere / capsule obstacles) and above the ground. Scenes keep their own
  cinematic camera and call `orbit.update(delta, auto_pos, auto_look, fov)` every frame; the controller hands the
  camera over smoothly and back.
* In missions the camera is a separate **inspect mode (C)**: the simulation is frozen, so the camera can never
  change the rocket / astronaut / spacecraft; C or R resumes. In menus and the rocket designer it is always available.

## Audio
`Core/sfx.gd` (autoload `Sfx`) synthesises all sounds and the ambient loop at runtime - no audio files. Master volume
is controlled from Settings.

## 3D pipeline
* **Models** are built procedurally by `Tools/blender/build_assets.py` (Blender 5.1, background mode) and exported
  as `.glb`; re-run it after editing the script:
  `blender --background --python Tools/blender/build_assets.py -- Assets/Models`
  Palette: white / grey hull, dark technical parts, blue + orange accents (no red/blue/white stripes).
* **Gameplay stays separate from rendering**: `FlightModel` (M1), `SpacewalkWorld` (M2) and `DockingWorld` (M3)
  are the original simulations; `FlightDirector3D`, `SpacewalkView3D` and `DockingView3D` only read their state.
* The Earth is a real sphere with a procedural shader (continents, clouds, atmosphere glow, city lights); the sky
  shader fades from atmosphere to stars with altitude. Needs the **Forward+** renderer.

### Replacing the temporary menu
The final menu (`GameMenu/MainMenu/main_menu.tscn`) only has to call
`Router.play()`, `Router.go_to(Router.MISSION_SELECT)`, `Router.go_to(Router.SETTINGS)` and
`get_tree().quit()`. Then change `Router.MAIN_MENU` (`Core/router.gd`) and
`application/run/main_scene` in `project.godot` to the new scene.

### Adding mission 4 / 5
1. Create a scene whose root script `extends MissionBase`, set `mission_id` in `_init()`,
   implement `_briefing_data()`, `_build_mission()`, `_on_mission_start()` and call `finish(...)`.
2. In `Core/mission_registry.gd` set `"available": true` and the `"scene"` path.
3. Add texts to a new `Core/strings_mX.gd` and merge it in `Core/strings.gd`.

## Localization
English (default) and Ukrainian through `TranslationServer`. All texts live in `Core/strings_*.gd`
as `KEY: [English, Українська]`; UI nodes use the key as their text, so they re-translate instantly
when the language is switched. The language is selectable **only in Settings** and is saved.
Audit: `Godot --headless --path . --script res://Tools/check_strings.gd`.

## Controls (Mission 1)
`W/S` throttle, `A/D` pitch, `T` prograde hold, `Z/X` full/cut, `1-3` time warp, `SPACE` deploy, `ESC` pause.
Missions 2 and 3 list their controls in the briefing screen.

## Developer tools
```
# balance / physics check of every part combination
Godot --headless --path . --script res://Tools/sim_test.gd
# full scene run with an autopilot (assembly -> flight -> result -> saved progress)
Godot --headless --fixed-fps 60 --path . --script res://Tools/e2e_m1.gd -- kestrel/l/aero 1
Godot --headless --fixed-fps 60 --path . --script res://Tools/e2e_generic.gd -- res://Missions/Mission2/mission2.tscn 1
# screenshot of any scene (non-headless): Tools/run_shot.ps1
```
Note: the e2e tests write to the normal save file; use *Settings -> Reset progress* afterwards.

## Physics note (Mission 1)
Simplified on purpose: a scaled-down Earth (radius 1600 km, g = 9.81 m/s^2) so a single stage can reach orbit.
Gravity follows 1/r^2, atmosphere density falls exponentially, drag = 1/2 rho v^2 Cd A, engine Isp rises as the
air thins, mass flow = thrust / (Isp g0). The HUD shows apoapsis/periapsis computed from the real orbit equations;
a stable orbit means periapsis above 80 km.
