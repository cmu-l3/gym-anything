# Task: solar_flux_decay_comparison

## Domain Context

**Primary occupation**: Atmospheric and Space Scientist (ONETSOC 19-2021.00)
**Workflow type**: Solar activity sensitivity study for orbital lifetime prediction

Space debris analysts and satellite operators must assess how varying solar activity affects satellite orbital decay and lifetime. This is critical for IADC compliance planning — a satellite that meets the 25-year deorbit rule at solar minimum may have dangerous debris lifetime under active sun conditions. Running parametric solar flux sweeps is a standard workflow in mission analysis departments.

## Goal

Simulate 60-day orbital decay for the Sentinel-LEO satellite (600 km, near-circular) under three solar activity scenarios using different F10.7 solar flux index values, and produce a comparative analysis showing how solar activity affects orbital decay rate.

## Success Criteria

Three distinct scenarios must be simulated:
- **Quiet Sun** (F10.7 = 70): Solar minimum conditions
- **Moderate Sun** (F10.7 = 150): Average solar cycle conditions
- **Active Sun** (F10.7 = 230): Solar maximum conditions

The analysis must demonstrate the physically correct ordering: Active sun decays the orbit faster than moderate sun, which decays faster than quiet sun.

Report written to `~/GMAT_output/solar_flux_analysis.txt`.

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| script_created | 10 | Script mtime > task start timestamp |
| three_scenarios_present | 20 | 3 distinct F10.7 values spanning quiet/active range |
| drag_force_model | 10 | JacchiaRoberts or MSISE atmosphere model |
| analysis_written | 10 | Analysis report with ≥3/5 required fields |
| sma_ordering | 15 | Active SMA < Moderate SMA < Quiet SMA |
| decay_quiet_valid | 10 | Quiet decay in [0.1, 5.0] km |
| decay_moderate_valid | 10 | Moderate decay in [1.0, 20.0] km |
| decay_active_valid | 10 | Active decay in [5.0, 80.0] km |
| ratio_valid | 5 | Active/Quiet ratio in [3, 50] |

**Pass condition**: score ≥ 60 AND three_scenarios_present AND sma_ordering (physically correct result).

## Spacecraft Parameters

- Sentinel-LEO: SMA = 6971.14 km (600 km altitude), ECC = 0.001, INC = 97.8 deg
- DryMass = 450 kg, DragArea = 8.0 m², Cd = 2.2
- Epoch: 01 Jan 2025 00:00:00.000 UTC

## Orbital Mechanics Reference

**Solar flux effect on drag**:
- Atmospheric density at 600 km varies by ~10× between solar min and max
- F10.7 index: solar minimum ≈ 70, average ≈ 150, solar maximum ≈ 230

**Expected 60-day SMA decays at 600 km** (order of magnitude):
- F10.7=70 (quiet): ~0.5–2 km
- F10.7=150 (moderate): ~3–10 km
- F10.7=230 (active): ~15–50 km

These ranges depend on spacecraft B* and atmospheric model. Values outside these ranges suggest implementation errors.

## Edge Cases

- Agent may use separate GMAT scripts for each scenario — acceptable
- Agent may use MSISE86 or NRLMSISE00 instead of JacchiaRoberts — both acceptable
- Agent may use different propagation durations — if not exactly 60 days, verifier checks ordering only
- Agent may miss analysis file format but compute correct values — partial credit
