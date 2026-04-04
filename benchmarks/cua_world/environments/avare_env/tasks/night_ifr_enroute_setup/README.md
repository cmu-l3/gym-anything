# Task: night_ifr_enroute_setup

## Domain Context

Instrument-rated pilots flying IFR (Instrument Flight Rules) at night must
configure their EFB to display the correct charts and minimise cockpit glare.
Two critical pre-flight steps are:

1. **Enable Night Mode** — dims the display and inverts to dark-background
   colours to preserve night vision and reduce reflection in the windshield.
2. **Switch to IFR Low-Altitude Enroute charts** — the standard chart for
   en-route IFR below 18,000 ft MSL (FL180). VFR Sectional charts do not show
   the airways, MEAs (Minimum Enroute Altitudes), or fixes used in IFR flight
   planning.

**Occupation context**: Commercial pilots (SOC 53-2011), air taxi pilots, and
instrument-rated private pilots flying in IMC or at night rely on EFB software
like Avare to display IFR Low charts and reduce cockpit lighting before departure.

---

## Task Goal

1. **Enable Night Mode** in Avare settings so the display is optimised for
   dark cockpit operations.
2. **Switch the chart type to IFR Low-Altitude Enroute** (the standard chart
   for IFR en-route navigation below FL180).
3. **Build and save a flight plan** with **KSFO** as departure and **KDEN**
   (Denver International) as destination.

All three sub-tasks must be completed. No UI steps are provided — the agent
must discover the Settings menu location, the Plan screen, and how to save.

---

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| Night Mode is enabled | 35 | SharedPreferences boolean or string |
| Chart type = IFR Low-Altitude | 35 | Any form of "IFR Low" or "Enroute Low" |
| KSFO present in any saved plan | 20 | Departure airport |
| KDEN present in any saved plan | 10 | Destination airport |
| **Pass threshold** | **75** | Night + IFR alone = 70; must save plan too |

> Threshold 75 prevents passing on Night+IFR alone (70 pts) or on the plan
> alone (30 pts). All three categories must be substantially complete.

---

## Verification Strategy

1. **export_result.sh** (Android device):
   - Takes final screenshot.
   - Force-stops Avare to flush prefs to disk.
   - Copies SharedPreferences XML → `/sdcard/avare_night_ifr_prefs.xml`.
   - Collects all plan CSVs → `/sdcard/avare_night_ifr_plans.txt`.

2. **verifier.py** (`check_night_ifr_enroute_setup`) (host):
   - Pulls both files via `copy_from_env`.
   - Searches SharedPreferences XML for `<boolean name="*night*" value="true"/>` or
     `<string name="*night*">true</string>`.
   - Searches for any chart-type string element containing "ifr" and "low".
   - Checks plan text for "KSFO" and "KDEN".

---

## Schema / Data Reference

| File / Path | Description |
|-------------|-------------|
| `/sdcard/avare_night_ifr_prefs.xml` | SharedPreferences copy |
| `/sdcard/avare_night_ifr_plans.txt` | All plan CSVs concatenated |
| `/sdcard/avare_night_ifr_plan_count.txt` | Number of saved plans |

Night mode prefs key (version-dependent): `NightMode`, `NightModePreference`,
or similar containing "night". Verifier uses case-insensitive regex search.

Real airports:
- **KSFO** — San Francisco International (37.6213°N, 122.3790°W)
- **KDEN** — Denver International (39.8561°N, 104.6737°W)

---

## Starting State

`setup_task.sh` attempts to reset Night Mode to `false` in SharedPreferences
before launch, so the agent must deliberately enable it. Chart is left on
Sectional (app default) so the agent must switch to IFR Low.

---

## Edge Cases

- If the Night Mode preference has never been written, the XML element may be
  absent; verifier returns 0 (not "assume default") because Night Mode is off
  by default.
- If the agent sets Night Mode via a different UI path that writes a differently
  named key, the verifier's regex search for "night" handles common variants.
