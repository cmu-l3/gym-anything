# Task: aavso_variable_star_campaign

## Overview

**Difficulty:** very_hard
**Occupation:** Astronomer / AAVSO Variable Star Observer
**Industry:** Scientific Research / Variable Star Monitoring
**Environment:** kstars_sim_env (KStars + INDI Simulators)

An AAVSO (American Association of Variable Star Observers) campaign has been activated for the dwarf nova **SS Cygni**, which has entered an outburst state (brightening from quiescent ~12.0 mag to ~8.5 mag). The agent must read the campaign brief, configure the observatory correctly, execute the observation session, and submit an AAVSO-format observations report.

## What Makes This Very Hard

1. **No step-by-step instructions** — only the goal and the location of the campaign brief
2. **Agent must discover target coordinates** from the campaign brief (SS Cyg: RA 21h 42m 42.8s, Dec +43° 35' 10")
3. **Agent must determine the correct filter** (V-band = slot 2 in this filter wheel configuration)
4. **Agent must configure the CCD upload directory** from the spec (not the default)
5. **Agent must produce output in AAVSO Extended Format** — a domain-specific report format
6. **Telescope starts pointed at wrong target** (M31 area)

## Task Workflow (What the Agent Must Do)

1. Read `~/Documents/campaign_brief.txt`
2. Slew telescope to SS Cygni (RA 21h 42m 42.8s, Dec +43° 35' 10")
3. Set filter wheel to slot 2 (V-band)
4. Set CCD upload directory to `/home/ga/Images/sscyg/session1/`
5. Take ≥8 exposures of 45 seconds each (LIGHT frames)
6. Capture a sky view with `bash ~/capture_sky_view.sh`
7. Write AAVSO Extended Format report to `/home/ga/Documents/aavso_report.txt`

## INDI Commands Reference

```bash
# Slew telescope
indi_setprop 'Telescope Simulator.ON_COORD_SET.TRACK=On'
indi_setprop 'Telescope Simulator.EQUATORIAL_EOD_COORD.RA;DEC=21.7119;43.5861'

# Set filter to V-band (slot 2)
indi_setprop 'Filter Wheel Simulator.FILTER_SLOT.FILTER_SLOT_VALUE=2'

# Set upload directory
indi_setprop 'CCD Simulator.UPLOAD_SETTINGS.UPLOAD_DIR=/home/ga/Images/sscyg/session1'

# Take 45-second exposure
indi_setprop 'CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On'
indi_setprop 'CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE=45'
```

## Verification Criteria (100 pts, pass ≥ 60)

| Criterion | Points | Details |
|-----------|--------|---------|
| FITS images captured | 25 | ≥8 valid FITS in `/home/ga/Images/sscyg/session1/`, after task start |
| V-band filter used | 15 | Filter slot 2 selected, or FITS FILTER header = 'V' |
| Telescope at SS Cygni | 20 | Final position within 20 arcmin of RA 21.7119h, Dec +43.5861° |
| Report file exists | 15 | `/home/ga/Documents/aavso_report.txt` created during task |
| Report content valid | 25 | Contains AAVSO headers, 'SS CYG' target, V-band filter entries |

## Anti-Gaming Protections

- Task start time recorded in `/tmp/task_start_time.txt`
- FITS files must have `mtime > task_start` to count
- Report must have `mtime > task_start` to earn existence points
- Wrong-target scenario: telescope pointed at M31 at task start

## Real Data

- **SS Cygni** is a real, well-studied dwarf nova in Cygnus, and one of the brightest U Gem-type cataclysmic variables. It is the primary AAVSO long-term monitoring target with >400,000 observations in their database.
- **AAVSO Extended Format** is the real submission format used by observers worldwide.
- **HD 204188** is a real comparison star used in SS Cygni AAVSO charts.
- CCD star field rendering uses real Hubble Guide Star Catalog (GSC) data.
