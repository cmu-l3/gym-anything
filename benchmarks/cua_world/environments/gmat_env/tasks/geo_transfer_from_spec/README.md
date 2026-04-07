# Task: geo_transfer_from_spec

## Domain Context

**Primary occupation**: Atmospheric and Space Scientist (ONETSOC 19-2021.00)
**Workflow type**: Spec-driven mission design — GTO-to-GEO transfer

Satellite operators receive official Mission Operations Procedure Specifications (MOPS) documents describing launch injection orbits and required GEO slots. The astrodynamics engineer's job is to read these specs and design the Apogee Kick Maneuver (AKM) — the large burn at GTO apogee that circularizes the orbit into geostationary orbit. This is a core commercial satellite operations workflow used by companies like Intelsat, SES, and Telesat.

## Goal

Read the CommStar-7 satellite specification document at `~/Desktop/geo_sat_specs.txt`, extract the GTO injection parameters, and design a GMAT simulation of the GTO-to-GEO transfer using an impulsive AKM burn with a DifferentialCorrector to precisely target GEO insertion (SMA = 42164.17 km).

## Success Criteria

The simulation must achieve:
- GEO SMA within 50 km of 42164.17 km
- GEO eccentricity < 0.005
- GEO inclination < 0.5 deg
- Total ΔV in the physically expected range [1400, 2000] m/s
- DifferentialCorrector targeting logic present
- Results written to `~/GMAT_output/geo_transfer_results.txt`

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| script_created | 10 | Script mtime > task start timestamp |
| gto_params_correct | 15 | SMA ~24505 and ECC ~0.7315 from spec in script |
| impulsive_burn | 10 | `Create ImpulsiveBurn` for AKM |
| targeting_logic | 15 | DC + Target + Vary + Achieve logic present |
| results_written | 10 | Results file with ≥3/5 required fields |
| deltav_valid | 20 | Total ΔV in [1400, 2000] m/s |
| geo_sma_valid | 15 | Final SMA within 50 km of 42164.17 km |
| geo_orbit_quality | 5 | ECC < 0.005, INC < 0.5 deg |

**Pass condition**: score ≥ 60 AND targeting_logic AND deltav_valid.

## Spec Document Location

`~/Desktop/geo_sat_specs.txt` — agent must find and read this file.

The document contains CommStar-7 GTO injection parameters (from Ariane 5 ECA standard GTO):
- SMA: 24505.4 km
- ECC: 0.7315
- INC: 7.0 deg
- Launch epoch: 15 Jun 2025 22:30:00.000 UTC

## Orbital Mechanics Reference

**GTO → GEO transfer**: Single apogee kick maneuver

GTO apogee radius = SMA × (1 + ECC) = 24505.4 × (1 + 0.7315) = ~42478 km

The apogee is already near GEO radius. The AKM at apogee:
1. Reduces apogee speed to GEO circular speed
2. Simultaneously reduces inclination from 7° to ~0°
3. Combined ΔV ≈ 1550–1700 m/s (inclination change is expensive)

**Expected ΔV**: ~1600 m/s (varies with inclination at burn point)

## Edge Cases

- Agent may propagate to apogee first then burn — correct approach
- Agent may attempt to find apogee via stopping condition (Periapsis/Apoapsis) — also correct
- DC may use SMA as the achieve target — valid
- Agent may add multiple spacecraft — acceptable
- Agent may use finite burn model instead of impulsive — partial credit (targeting still required)
