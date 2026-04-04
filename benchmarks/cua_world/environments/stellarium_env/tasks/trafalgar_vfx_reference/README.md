# Task: Battle of Trafalgar Sky Reference for VFX Production

## Domain Context

Visual effects artists working on historical films require accurate sky reconstruction for period
night scenes. The position, phase, and visibility of the Moon, planets, and star patterns directly
affect lighting design, set dressing, and digital matte painting. Stellarium is used professionally
to generate reference screenshots for any historical date and geographic location, which are then
handed to VFX compositors and lighting TDs.

This task simulates the workflow of a VFX supervisor generating sky reference documentation for a
feature film set during the Battle of Trafalgar (October 21, 1805) — the naval engagement off Cape
Trafalgar, Spain, where Admiral Nelson died.

## Occupation / Industry

**Occupation**: VFX Supervisor / Digital Matte Painter
**Industry**: Film & Television Production

## Task Description (for agent)

You are a VFX supervisor on a historical epic film about the Battle of Trafalgar (October 21, 1805).
The director needs accurate sky reference images for evening battle sequences set offshore near Cape
Trafalgar, Spain. Configure Stellarium to simulate a view from the sea off Cape Trafalgar (latitude
36.18°N, longitude 6.03°W, altitude 0m, sea-level position).

Set the date and time to October 21, 1805 at 20:00 UTC. Configure the sky for a realistic sailor's
view at sea that night: atmosphere must be enabled (for authentic sky glow), disable the ground/
landscape (sailors at sea see the full sky dome down to the horizon), enable constellation artwork
(the director wants mythological figure overlays for artistic reference), enable the azimuthal
coordinate grid (to document star positions by compass bearing), and enable cardinal direction labels.

Locate the Moon using the search function and center on it, then take a screenshot. Also locate
Jupiter and take a screenshot. Finally, capture one wide-field screenshot showing the overall sky
with the coordinate grid visible. Write your VFX reference notes documenting the Moon and Jupiter
positions to /home/ga/Desktop/trafalgar_sky_notes.txt.

## Success Criteria

1. **Location set to Cape Trafalgar**: lat ≈ 36.18°N (0.6314 rad), lon ≈ -6.03°W (-0.1052 rad)
2. **Constellation artwork enabled**: `flag_constellation_art = true`
3. **Azimuthal grid enabled**: `flag_azimuthal_grid = true`
4. **Atmosphere enabled**: `flag_atmosphere = true`
5. **3+ screenshots taken**: 3+ new files in /home/ga/Pictures/stellarium/
6. **VFX notes file written**: /home/ga/Desktop/trafalgar_sky_notes.txt exists with Moon/Jupiter content

## Scoring (100 points)

- Location set to Cape Trafalgar region (lat within 0.10 rad of 0.6314 rad): **20 points**
- Constellation artwork enabled: **15 points**
- Azimuthal coordinate grid enabled: **15 points**
- Atmosphere enabled (landscape/ground disabled): **10 points**
- 3+ screenshots taken: **20 points**
- VFX notes file written with Moon or Jupiter content: **20 points**

Pass threshold: 70 points

## Real Data Sources

- Cape Trafalgar coordinates: 36.18°N, 6.03°W (verified via geographic databases)
- Historical date: Battle of Trafalgar, October 21, 1805 (Gregorian calendar)
- Sky positions at that date: computed by Stellarium from NASA JPL ephemeris data

## Edge Cases

- Historical date navigation requires stepping far back in time from current date
- Atmosphere must be ENABLED (ON) for this task — opposite of telescope tasks
- The ground/landscape must be DISABLED (sailors at sea see full sky dome)
- Moon and Jupiter may be close together or separated depending on exact 1805 positions
