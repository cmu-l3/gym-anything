# Task: Astrophotographer Deep-Sky Session Planner

## Domain Context

Professional astrophotographers at major observatories must plan imaging sessions well in advance,
selecting targets that will be optimally positioned during the observation window. This requires
configuring planetarium software for the observatory's precise coordinates, simulating the sky
at the planned observation time, configuring display settings for professional dark-sky work
(no simulated atmosphere, no obstructing ground), and documenting target selections with screenshots.

This task simulates the workflow used by astrophotographers at ESO's Paranal Observatory — one of
the world's premier dark-sky sites — when planning imaging campaigns for wide-field deep-sky targets.

## Occupation / Industry

**Occupation**: Professional Astrophotographer / Observatory Imaging Scientist
**Industry**: Professional Astronomy / Scientific Imaging

## Task Description (for agent)

You are a professional astrophotographer at ESO's Paranal Observatory in Chile. You need to plan
a deep-sky imaging session for the night of July 16, 2023, starting at 01:00 UTC. The observatory
data file at /home/ga/data/observatory_locations.json contains the precise coordinates you need.

Configure Stellarium to simulate your observatory site and observation time. For dark-sky professional
imaging, configure the display for pure sky conditions: disable both the atmospheric simulation and
landscape ground (which obstruct clean sky views), and enable the equatorial coordinate grid for
precise pointing reference.

Then, from your target list — NGC 3372 (Eta Carinae Nebula), NGC 5128 (Centaurus A), and NGC 5139
(Omega Centauri) — locate each object using the search function, center it in view, and take a
Stellarium screenshot for each one (Stellarium's built-in screenshot saves to the configured
screenshots folder at /home/ga/Pictures/stellarium/).

After investigating all three targets, write a session notes file to /home/ga/Desktop/session_notes.txt
documenting the three NGC target names and the planned observation night (July 16, 2023).

## Success Criteria

1. **Observatory location configured**: Stellarium set to Paranal Observatory (~-24.63°N, ~-70.40°W, 2635m)
2. **Atmosphere disabled**: `flag_atmosphere = false` in config.ini [landscape] section
3. **Equatorial grid enabled**: `flag_equatorial_grid = true` in config.ini [viewing] section
4. **Three screenshots taken**: 3+ new files in /home/ga/Pictures/stellarium/ created after task start
5. **Session notes saved**: /home/ga/Desktop/session_notes.txt exists and contains NGC target names

## Scoring (100 points)

- Observatory location set correctly (lat within 0.05 rad of -0.430 rad): **25 points**
- Atmosphere disabled: **15 points**
- Equatorial grid enabled: **15 points**
- 3+ new screenshots taken: **25 points**
- Session notes file written with NGC content: **20 points**

Pass threshold: 70 points

## Verification Strategy

1. Read `/home/ga/.stellarium/config.ini` after Stellarium exits:
   - Check `[location_run_once] latitude` ≈ -0.4297 rad (Paranal -24.6272°)
   - Check `[landscape] flag_atmosphere = false`
   - Check `[viewing] flag_equatorial_grid = true`
2. Count files in `/home/ga/Pictures/stellarium/` with mtime > task_start
3. Check existence and content of `/home/ga/Desktop/session_notes.txt`

## Real Data Sources

- Observatory coordinates: ESO Paranal (IAU code 309) from observatory_locations.json
  - Source: IAU Minor Planet Center + ESO official observatory page
  - Latitude: -24.6272°, Longitude: -70.4042°, Altitude: 2635m
- NGC target coordinates: Messier/NGC catalog, NASA/IPAC NED

## Edge Cases

- Stellarium must exit gracefully (SIGTERM) for JD to be saved to config
- Screenshots are named by date/time, so count all files newer than task_start timestamp
- Session notes file must contain "NGC" keyword to pass verification
