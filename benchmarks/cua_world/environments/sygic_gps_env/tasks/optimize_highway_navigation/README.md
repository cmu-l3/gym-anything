# Optimize Highway Navigation

## Overview
A long-haul trucker configures 8 settings across multiple areas of Sygic GPS Navigation for efficient highway driving: route avoidances, route computation, navigation display, and map view preferences.

## Domain Context
Long-haul truckers need GPS configured for highway driving: highways and toll roads must be allowed, fastest routes preferred, 2D driving mode for clarity, compass for orientation, larger fonts for readability, and flat terrain rendering to reduce visual clutter.

## Goal / End State
- Avoid highways: OFF (highways allowed)
- Avoid toll roads: OFF (toll roads allowed)
- Avoid unpaved roads: ON (stays enabled)
- Route computation: Fastest route
- Compass: enabled
- Driving mode: 2D
- 3D terrain: disabled
- Map font size: Bigger

## Verification Strategy
Eight criteria (~12-13 points each, 100 total):
1. Avoid highways = false (13 pts)
2. Avoid toll roads = false (13 pts)
3. Avoid unpaved roads = true (12 pts)
4. Route compute = Fastest/"1" (13 pts)
5. Compass enabled = true (12 pts)
6. Driving mode = 2D/"0" (13 pts)
7. 3D terrain = false (12 pts)
8. Font size = Bigger/"1" (12 pts)

Gate: If BOTH route_compute AND driving_mode are unchanged from setup baseline values, score = 0.

## Data Sources
- Preferences: `/data/data/com.sygic.aura/shared_prefs/com.sygic.aura_preferences.xml`
  - Route avoidances: `tmp_preferenceKey_routePlanning_motorways_avoid`, `tmp_preferenceKey_routePlanning_tollRoads_avoid`, `tmp_preferenceKey_routePlanning_unpavedRoads_avoid` (boolean)
  - Route compute: `preferenceKey_routePlanning_routeComputing` (string: "0"=Shortest, "1"=Fastest)
  - Compass: `preferenceKey_navigation_compassAlwaysOn` (boolean)
  - Driving mode: `preferenceKey_drivingMode` (string: "0"=2D, "1"=3D)
  - 3D terrain: `preferenceKey_map_3dTerrain` (boolean)
  - Font size: `preferenceKey_map_fontSize` (string: "0"=default, "1"=bigger)

## Edge Cases
- 3D terrain key may not exist in shared_prefs until toggled for the first time; setup script inserts it if missing
- Settings span two different pages in the app (Route planning & Navigation, View & Units)
- Agent must avoid toggling "Avoid unpaved roads" (should remain ON)
