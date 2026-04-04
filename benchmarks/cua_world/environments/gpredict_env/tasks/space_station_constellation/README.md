# Task: Space Station Multi-Component Constellation Tracking

## Domain Context

Aerospace engineers, flight controllers, and space researchers at universities and space agencies use satellite tracking software to monitor crewed space stations. As of 2025-2026, two separate crewed space station programs are operational: the International Space Station (ISS) with multiple interconnected modules, and the Chinese Space Station (CSS/Tiangong) with its core module and two science modules. Tracking all components provides accurate position data for observation windows, communication planning, and rendezvous simulation.

This task reflects real work at aerospace engineering labs, university space centers, and space agency training facilities where engineers must configure tracking software for their full operational constellation.

## Persona

Aerospace Engineer / Orbital Mechanics Researcher at a university space engineering laboratory — responsible for configuring the lab's satellite tracking infrastructure for monitoring crewed space stations as part of human spaceflight research.

## Scenario

The laboratory's GPredict installation has a SpaceStations module that only tracks ISS (ZARYA), the original Russian module from 1998. The module is critically incomplete — it is missing all other ISS components (POISK, NAUKA) and the entire Chinese Space Station (TIANHE, WENTIAN, MENGTIAN). Additionally, the lab needs ground stations configured for the two major spaceflight centers, and the software should display UTC time for consistency with mission operations.

## Task Description (for agent)

You are configuring GPredict for a university aerospace engineering lab that monitors crewed space stations.

The SpaceStations module currently tracks only ISS (ZARYA) and needs to be completed:

1. Add the remaining **ISS components** to the SpaceStations module:
   - **ISS (POISK)** — Russian docking module, NORAD 36086
   - **ISS (NAUKA)** — Russian Multipurpose Laboratory Module, NORAD 49044

2. Add all **Chinese Space Station (CSS)** components to the SpaceStations module:
   - **CSS (TIANHE)** — Core module, NORAD 48274
   - **CSS (WENTIAN)** — Laboratory module 1, NORAD 53239
   - **CSS (MENGTIAN)** — Laboratory module 2, NORAD 54216

   ISS (ZARYA, NORAD 25544) is already in the module and must remain.

3. Add a ground station for **Johnson Space Center** (Houston, TX): Latitude = 29.5502°N, Longitude = 95.0970°W, Altitude = 14 meters.

4. Add a ground station for **Kennedy Space Center** (Florida): Latitude = 28.5729°N, Longitude = 80.6490°W, Altitude = 3 meters.

5. Configure GPredict to display **UTC time** (instead of local time) for all timestamps.

Login: username `ga`, password `password123`. GPredict is already open.

## Success Criteria

- SpaceStations.mod contains all 6 NORAD IDs: 25544, 36086, 49044, 48274, 53239, 54216
- JSC/Houston ground station exists (LAT≈29.55, LON≈-95.10, ALT≈14m)
- KSC ground station exists (LAT≈28.57, LON≈-80.65, ALT≈3m)
- GPredict configured for UTC time display

## Verification Strategy

Scoring (100 points, pass ≥ 70):
- SpaceStations module has all 6 components (10 pts each): 60 pts total
  - ISS ZARYA (25544) already present: 10 pts
  - ISS POISK (36086) added: 10 pts
  - ISS NAUKA (49044) added: 10 pts
  - CSS TIANHE (48274) added: 10 pts
  - CSS WENTIAN (53239) added: 10 pts
  - CSS MENGTIAN (54216) added: 10 pts
- JSC/Houston ground station: 15 pts
- KSC ground station: 15 pts
- UTC time configured: 10 pts

## Key Data (from CelesTrak stations.txt TLE data)

| Component | NORAD ID | Station | Status |
|-----------|----------|---------|--------|
| ISS (ZARYA) | 25544 | ISS | **Already in module** |
| ISS (POISK) | 36086 | ISS | Active Russian module |
| ISS (NAUKA) | 49044 | ISS | Active Russian lab module |
| CSS (TIANHE) | 48274 | CSS/Tiangong | Core module |
| CSS (WENTIAN) | 53239 | CSS/Tiangong | Science module |
| CSS (MENGTIAN) | 54216 | CSS/Tiangong | Science module |

## GPredict Config Notes

- UTC time setting in `gpredict.cfg`: section `[misc]`, key `utc=1` (1=UTC, 0=local time)
- Module file: `~/.config/Gpredict/modules/SpaceStations.mod`
- Ground stations: `~/.config/Gpredict/*.qth`
