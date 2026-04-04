# Task: exposure_limit_exceedance

## Domain
Occupational Health and Safety — Industrial Hygiene / Air Monitoring

## Overview
An OHS Specialist must review air monitoring results from a manufacturing facility. Six work zones were sampled for six different solvents. The results include both exceedances and readings within limits — the agent must distinguish between them by looking up actual OSHA PEL and IDLH values using CAMEO Chemicals. One worker in Zone 4 has reported peripheral neuropathy symptoms, and the agent must identify which chemical is the most likely cause and explain the mechanism.

## Starting State
- Firefox is open at CAMEO Chemicals (https://cameochemicals.noaa.gov/)
- `~/Desktop/air_monitoring_report.txt` contains the 6-zone air monitoring data (measured ppm values, no PELs listed — those must be looked up)
- No output file exists at task start

## Goal / End State
Produce an exposure exceedance report at:
```
~/Documents/exposure_exceedance_report.txt
```

The report must:
1. Look up OSHA PEL and IDLH for all 6 chemicals using CAMEO Chemicals
2. Identify the 4 zones with PEL exceedances (Zones 2, 3, 4, 5)
3. Correctly classify Zones 1 and 6 as within acceptable limits
4. Identify n-Hexane (Zone 4) as the likely cause of the worker's peripheral neuropathy
5. Provide corrective action recommendations for exceedance zones

## Chemicals and Monitoring Data (NOT revealed to agent — PELs must be looked up)

| Zone | Chemical | Measured | OSHA PEL | IDLH | Status |
|------|----------|----------|----------|------|--------|
| 1 | Toluene | 185 ppm | 200 ppm | 500 ppm | Within limit |
| 2 | Xylene | 115 ppm | 100 ppm | 900 ppm | **EXCEEDS PEL** |
| 3 | MEK (2-Butanone) | 255 ppm | 200 ppm | 3000 ppm | **EXCEEDS PEL** |
| 4 | n-Hexane | 680 ppm | 500 ppm | 1100 ppm | **EXCEEDS PEL + neuropathy** |
| 5 | Methanol | 400 ppm | 200 ppm | 6000 ppm | **EXCEEDS PEL** |
| 6 | Tetrachloroethylene (PERC) | 38 ppm | 100 ppm | 150 ppm | Within limit |

**Key clinical finding**: n-Hexane is metabolized to 2,5-hexanedione, a classic cause of peripheral neuropathy in occupational exposures. Zone 4 is well above the PEL and has a worker with neuropathy symptoms — this connection requires CAMEO health hazard lookup.

## Difficulty: very_hard

- PEL values are NOT provided in the monitoring report — must be looked up for all 6 chemicals
- Neuropathy mechanism is not in the task description — requires reading CAMEO health effects
- Agent must distinguish exceedances from within-limit readings (avoid over-flagging)
- Requires 6 separate CAMEO chemical lookups plus synthesizing the neurological finding

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| File gate | 0/100 | If no output file → score=0 |
| 4 exceedance zones (7 pts each, 30 if all 4) | 30 | Xylene, MEK, n-Hexane, Methanol flagged |
| n-Hexane → neuropathy | 30 | n-Hexane + neuropathy both mentioned |
| PEL/IDLH references | 20 | Actual limit values mentioned |
| Corrective actions | 20 | Engineering/admin controls recommended |

Pass threshold: 60/100
