# Task: Maritime Celestial Navigation Training Scenario

## Domain Context

Celestial navigation is the art and science of determining one's position at sea using the altitudes
of astronomical objects (stars, Sun, Moon, planets) measured with a sextant. Maritime pilots and
navigation instructors use planetarium software to prepare training materials: setting up simulated
sky views for specific ship positions and dates, identifying navigational stars, and documenting
their expected altitudes and bearings for student practice sheets.

This task simulates the preparation of a star identification exercise: configuring Stellarium for a
vessel position in the Pacific, setting up the display for a navigator's toolkit (azimuthal grid for
altitude/bearing measurements, star names, no decorative constellation overlays that would confuse
novices), and documenting four classical navigational stars.

## Occupation / Industry

**Occupation**: Maritime Pilot / Celestial Navigation Instructor
**Industry**: Maritime Transport / Naval Training

## Task Description (for agent)

You are a celestial navigation instructor at a maritime academy preparing a star identification
training exercise. Configure Stellarium to simulate a vessel's position near the Mariana Islands in
the western Pacific (latitude 15.00°N, longitude 145.00°W, altitude 0m).

Set the date and time to December 15, 2023 at 22:30 UTC (evening star-sight time for the scenario).

Configure Stellarium for a navigator's working toolkit: enable the azimuthal (horizontal) coordinate
grid (for measuring altitudes and bearings), ensure star name labels are visible, disable constellation
line drawings (which confuse novice navigators), disable constellation artwork, and disable the
atmospheric simulation for a clean unobstructed view.

Then, locate and center on each of the following four classical navigational stars — Polaris, Sirius,
Canopus, and Vega — taking a Stellarium screenshot for each one showing the star centered with the
azimuthal grid visible.

After documenting all four stars, write a navigation practice log to /home/ga/Desktop/nav_log.txt
listing all four star names, the scenario date, and the simulated ship position.

## Success Criteria

1. **Location set to Pacific position**: lat ≈ 15°N (0.2618 rad), lon ≈ -145°W (-2.5307 rad)
2. **Azimuthal grid enabled**: for altitude/bearing measurements
3. **Constellation drawing disabled**: for clean navigator view
4. **4+ screenshots taken**: one per navigational star
5. **Navigation log written**: /home/ga/Desktop/nav_log.txt with star names

## Scoring (100 points)

- Pacific vessel location (lat within 0.10 rad of 0.2618 rad): **20 points**
- Azimuthal grid enabled: **20 points**
- Constellation drawing disabled: **15 points**
- 4+ screenshots taken: **25 points**
- Navigation log written with star names: **20 points**

Pass threshold: 70 points

## Starting State (Intentionally Misconfigured)

The task starts with Stellarium configured for confused/noisy display (constellation lines ON,
constellation art ON, star names OFF). The agent must actively correct all display settings.

## Real Data Sources

- Pacific ship position (15°N, 145°W): Mid-Pacific Ocean, near Saipan/Mariana Islands
  - Standard celestial navigation exercise area for mid-Pacific routing
- Navigation stars (Polaris, Sirius, Canopus, Vega): Standard HO 229 / Nautical Almanac navigational stars
- Date: December 15, 2023 — good winter sky for all four target stars from this latitude

## Edge Cases

- Canopus is a southern star (dec ~ -52°) and may be below horizon from 15°N
  - This is intentional: agent must attempt the search and discover observability constraints
  - Screenshot still required even if star near horizon
- Polaris will be visible at low altitude (~15°) from 15°N latitude
