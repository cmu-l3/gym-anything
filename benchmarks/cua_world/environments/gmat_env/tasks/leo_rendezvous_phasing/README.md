# Task: leo_rendezvous_phasing

## Domain Context

**Primary occupation**: Atmospheric and Space Scientist (ONETSOC 19-2021.00), specifically Rendezvous and Proximity Operations (RPO) Engineer
**Workflow type**: Two-spacecraft phasing maneuver design

Rendezvous and proximity operations engineering is a specialized domain within satellite mission analysis. Space servicing missions (DARPA RSGS, Northrop Grumman MEV series, Astroscale ELSA-d) require precise phasing maneuvers to approach target spacecraft. The RPO engineer designs the phasing orbit — temporarily lowering or raising the chaser's orbit so it drifts relative to the target at the desired rate, then restoring the original altitude.

## Goal

Design a two-impulse phasing maneuver in GMAT to bring the CHASER spacecraft from 100 km behind the CHIEF (target) to a 5 km trailing formation, both in a 450 km circular orbit.

An initial state reference document is available at `~/Documents/missions/initial_state_reference.txt`.

## Success Criteria

The phasing maneuver must achieve:
- Final along-track separation ≤ 8 km (within tolerance of 5 km target)
- CHASER final altitude within 5 km of 450 km (orbit restored)
- Both burns between 1 m/s and 100 m/s each
- Phasing time between 1 and 48 hours

Results written to `~/GMAT_output/rendezvous_results.txt`.

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| script_created | 10 | Script mtime > task start timestamp |
| two_spacecraft | 15 | Both CHIEF and CHASER spacecraft defined |
| two_burns | 15 | Two `Create ImpulsiveBurn` statements |
| propagation_logic | 10 | ≥2 Propagate commands |
| results_written | 10 | Results file with ≥3/5 required fields |
| deltav1_valid | 10 | First burn in [1, 100] m/s |
| deltav2_valid | 10 | Second burn in [1, 100] m/s |
| phasing_time_valid | 10 | Total time in [1, 48] hours |
| separation_achieved | 10 | Final separation ≤ 8 km |
| altitude_restored | 10 | CHASER altitude within 5 km of 450 km |

**Pass condition**: score ≥ 60 AND two_spacecraft AND two_burns.

## Initial Orbital State

- **CHIEF**: SMA=6821.14 km, ECC=0.0001, INC=28.5°, RAAN=45°, AOP=0°, TA=0°
- **CHASER**: Same elements except TA=−14.84° (100 km behind at 450 km altitude)
- Both: DryMass=800 kg, DragArea=4.0 m², Cd=2.2

## Orbital Mechanics Reference

**Phasing ellipse approach**:
1. Burn 1 (Δv₁ retrograde): Lower CHASER orbit by ΔSMAₚ ≈ 10–20 km
   - ΔSMAₚ = −2 × (a / v) × Δv₁ (approximate)
2. Wait N orbits for CHASER to gain on CHIEF:
   - Period difference: ΔT = 3π × ΔSMAₚ / (a × n)
   - For 95 km gain needed, N depends on ΔSMAₚ
3. Burn 2 (Δv₂ prograde): Restore circular orbit at 450 km

**At 450 km altitude**:
- Orbital period ≈ 93.4 min
- Circular velocity ≈ 7.66 km/s
- For ΔSMAₚ = −13 km: drift rate ≈ 9.3 km/orbit
- Orbits to close 95 km gap: ~10 orbits ≈ 15.6 hours

**ΔV for each burn** (Hohmann-like):
- Δv₁ ≈ Δv₂ ≈ n × ΔSMAₚ / 2 ≈ 12–15 m/s for ΔSMAₚ = −13 km

## Edge Cases

- Agent may use different CHIEF/CHASER naming (e.g., TARGET/SERVICER) — partial credit for structure
- Agent may use a single burn (sub-optimal) — partial credit
- Agent may use DifferentialCorrector instead of manual design — acceptable, score based on results
- Exact separation depends on propagation stopping condition — within ±3 km of target is acceptable
