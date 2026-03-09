# Task: Polar Weather Satellite Constellation Tracking

## Domain Context

Meteorologists at national weather services use satellite tracking software to plan data reception windows for polar-orbiting weather satellites. These satellites pass overhead multiple times per day, and ground station operators must know exactly when each satellite will be visible above their horizon to schedule data downlinks. GPredict enables meteorologists to track their entire polar-orbiting constellation and predict when each satellite will be in range of their ground stations.

This task reflects real work that a NOAA/NWS satellite meteorologist would do: maintaining the correct satellite tracking module for the polar satellite constellation, ensuring all operational ground stations are configured, and setting the software to use appropriate scientific units.

## Persona

Satellite Meteorologist, National Weather Service — responsible for polar satellite data reception at two Alaskan ground stations. Must configure tracking software to correctly display the operational polar constellation (not space station components, which were accidentally added).

## Scenario

The PolarWX tracking module was misconfigured by a previous operator who accidentally added ISS (ZARYA, a crewed space station) instead of the polar-orbiting weather satellites. The module must be corrected to contain only the operational polar-orbiting meteorological satellites. Additionally, two Alaska receive sites need to be added, and the software should be configured to use metric units for professional meteorological work.

## Task Description (for agent)

You are a meteorologist at a National Weather Service office configuring GPredict for polar-orbiting weather satellite tracking.

The current configuration has errors:

1. The **PolarWX** module is misconfigured — it currently tracks ISS (a space station, not a weather satellite). Remove ISS from the PolarWX module and replace with the four operational polar-orbiting weather satellites: **SUOMI NPP** (NORAD 37849), **FENGYUN 3A** (NORAD 32958), **FENGYUN 3B** (NORAD 37214), and **DMSP 5D-3 F18 / USA 210** (NORAD 35951).

2. Add a ground station for your **Fairbanks, AK** receive site: Latitude = 64.8378°N, Longitude = 147.7164°W, Altitude = 133 meters.

3. Add a ground station for your **Anchorage, AK** receive site: Latitude = 61.2181°N, Longitude = 149.9003°W, Altitude = 38 meters.

4. Configure GPredict to use **metric units** (kilometers) for all distance and speed measurements (in Edit > Preferences).

Login: username `ga`, password `password123`. GPredict is already open.

## Success Criteria

- PolarWX.mod SATELLITES field contains 37849, 32958, 37214, 35951
- PolarWX.mod does NOT contain 25544 (ISS)
- Fairbanks.qth exists with correct coordinates (LAT≈64.84, LON≈-147.72, ALT≈133m)
- Anchorage.qth exists with correct coordinates (LAT≈61.22, LON≈-149.90, ALT≈38m)
- GPredict configured to use metric units

## Verification Strategy

The verifier reads:
- `/home/ga/.config/Gpredict/modules/PolarWX.mod`
- `/home/ga/.config/Gpredict/*.qth` (scanning for Fairbanks and Anchorage by coordinate)
- `/home/ga/.config/Gpredict/gpredict.cfg`

Scoring (100 points, pass ≥ 70):
- PolarWX contains all 4 weather sats AND not ISS: 30 pts
- Fairbanks AK ground station exists with correct coords: 20 pts
- Anchorage AK ground station exists with correct coords: 20 pts
- Metric units enabled in preferences: 15 pts
- Partial credit for 3/4 weather sats or partially correct coords: graduated

## Key Data (from CelesTrak TLE data in /workspace/data/weather.txt)

| Satellite | NORAD ID | Orbit | Purpose |
|-----------|----------|-------|---------|
| SUOMI NPP | 37849 | Sun-sync 824km | NOAA/NASA climate & weather |
| FENGYUN 3A | 32958 | Sun-sync 836km | Chinese polar meteorology |
| FENGYUN 3B | 37214 | Sun-sync 836km | Chinese polar meteorology |
| DMSP 5D-3 F18 (USA 210) | 35951 | Sun-sync 850km | US military weather |
| ISS (ZARYA) | 25544 | LEO 408km | **NOT a weather satellite** — must be removed |

## GPredict Config Locations
- Modules: `~/.config/Gpredict/modules/*.mod`
- Ground stations: `~/.config/Gpredict/*.qth`
- Preferences: `~/.config/Gpredict/gpredict.cfg`
- Metric units in gpredict.cfg: look for `unit=0` under `[misc]` section (0=km, 1=miles)
