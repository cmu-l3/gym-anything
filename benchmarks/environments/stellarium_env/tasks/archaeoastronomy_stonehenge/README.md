# Task: Archaeoastronomy — Stonehenge Solstice Sunrise Alignment (2500 BCE)

## Domain Context

Archaeoastronomers study the astronomical alignments of ancient monuments to understand their ritual
and calendrical significance. Stonehenge's Heel Stone alignment is famously oriented toward the
summer solstice sunrise. Verifying this alignment for the monument's original construction date
(~2500 BCE) requires simulating the sky at that ancient time, accounting for precession of the
equinoxes over 4,500 years — which shifts the Sun's rising point on the horizon.

This task reflects real research methodology: archaeoastronomers use software like Stellarium to
simulate ancient skies and document where the Sun rose on the horizon at specific historical dates
and locations. The output (annotated screenshots and research notes) forms part of conference papers
and site interpretation reports.

## Occupation / Industry

**Occupation**: Archaeoastronomer / Academic Researcher
**Industry**: Academia — Archaeology / History of Science

## Task Description (for agent)

You are an archaeoastronomer studying the astronomical alignments of Stonehenge. Your research
requires simulating the summer solstice sunrise as it would have appeared from Stonehenge around
2500 BCE, when the main sarsen circle was erected.

Configure Stellarium for Stonehenge (latitude 51.1789°N, longitude 1.8262°W, altitude 102m).
Navigate to June 21, 2500 BCE and set the time to approximately 04:45 UTC (local pre-sunrise time
in midsummer England).

Configure the display for this archaeoastronomy scenario: enable the atmosphere (for authentic dawn
sky colors and refraction effects near the horizon), disable the landscape ground (to have an
unobstructed view of the horizon where the Sun rises), enable the azimuthal coordinate grid (for
precise sunrise azimuth measurements), and also enable the equatorial coordinate grid (to record
the Sun's celestial coordinates for your paper).

Find the Sun using the search function, center on it, and take a screenshot documenting the
pre-dawn sky. Write your alignment research findings to /home/ga/Desktop/stonehenge_alignment.txt,
including the observation coordinates (Stonehenge), the date (June 21, 2500 BCE), and your
observations about the solstice sunrise.

## Success Criteria

1. **Location set to Stonehenge**: lat ≈ 51.18°N (0.8932 rad), lon ≈ -1.83°W (-0.0319 rad)
2. **Azimuthal grid enabled**: for bearing measurements
3. **Equatorial grid enabled**: for celestial coordinate documentation
4. **Ancient date set (2500 BCE)**: JD < 1,000,000 in config (verified after graceful exit)
5. **2+ screenshots taken**: Sun documented photographically
6. **Research notes written**: /home/ga/Desktop/stonehenge_alignment.txt with "Stonehenge" or "solstice"

## Scoring (100 points)

- Stonehenge location set (lat within 0.08 rad of 0.8932 rad): **25 points**
- Azimuthal grid enabled: **10 points**
- Equatorial grid enabled: **10 points**
- Ancient date navigated to (preset_sky_time < 1,000,000): **20 points**
- 2+ screenshots taken: **15 points**
- Research notes written with relevant keywords: **20 points**

Pass threshold: 70 points

## Real Data Sources

- Stonehenge coordinates: 51.1789°N, 1.8262°W, 102m altitude
  - Source: Ordnance Survey / English Heritage official site data
- Construction date: c. 2500 BCE (Phase 3 — main sarsen circle)
  - Source: Darvill, T. et al. (2012), "Stonehenge Remodelled", Antiquity 86:1021-1040
- Summer solstice: June 21 (solstice date, proleptic Gregorian calendar)
- JD for June 21, 2500 BCE ≈ 808,589 (computed from astronomical algorithms)

## Verification Notes

- Ancient dates use proleptic Gregorian calendar in Stellarium
- JD verification requires Stellarium to exit gracefully (SIGTERM) so config is saved
- Wide date tolerance (±90 days) applied since exact time matters less than epoch
