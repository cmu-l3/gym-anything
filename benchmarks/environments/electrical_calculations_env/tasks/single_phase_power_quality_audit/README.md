# Single-Phase Power Quality Audit

## Domain Context

Electricians and power quality engineers regularly investigate power factor penalties. Utilities in many jurisdictions impose surcharges on commercial and industrial customers when the power factor drops below 0.85 or 0.90. Auditing a circuit requires documenting all four quantities: voltage, current, and all three power components (S, P, Q). The power factor (PF = P/S) can be independently verified using a power factor calculator, which serves as a cross-check against the utility's metered reading.

## Task Goal

You are investigating a 230 V single-phase circuit with:
- Line voltage: 230 V
- Line current: 28 A
- Power factor: 0.65 lagging (reported by utility meter)

You must calculate and document:
1. Apparent power (S)
2. Real/true power (P)
3. Reactive power (Q)
4. Verify the power factor using the calculator (cross-check)

## What Success Looks Like

The agent has successfully completed this task when:
1. The apparent power (S ≈ 6,440 VA) has been calculated
2. The real power (P ≈ 4,186 W) has been calculated
3. The reactive power (Q ≈ 4,894 VAR) has been calculated
4. The final screen shows one of the single-phase power calculation results

## Calculations

- Apparent Power:  S = V × I = 230 × 28 = 6,440 VA
- Real Power:      P = V × I × PF = 230 × 28 × 0.65 = 4,186 W
- Reactive Power:  Q = V × I × sin(arccos(PF))
                     = 6,440 × sin(arccos(0.65))
                     = 6,440 × √(1 - 0.65²)
                     = 6,440 × √0.5775
                     = 6,440 × 0.7599
                     = 4,894 VAR

## Verification Strategy

The verifier checks the final UI dump for the reactive power result (≈4,894 VAR) and awards
partial credit for each power component visible on screen.

## Scoring (100 points)

- Reactive power result on screen (≈4,894 VAR ±3%):   35 pts [MANDATORY for pass]
- Real power result visible (≈4,186 W ±3%):           20 pts
- Apparent power result visible (≈6,440 VA ±3%):      20 pts
- Single-phase power calculator keywords visible:      15 pts
- Task input values (230V / 28A) visible:              10 pts

Pass threshold: 60 points (reactive power result required)

## Why This Is Hard

- The app has many calculators; the agent must navigate to single-phase power section
- Four distinct calculators must be used (apparent, real, reactive, power factor)
- The agent must know: sin(arccos(0.65)) = √(1-0.65²) ≈ 0.760
- The power factor verification step requires using results from previous calculations
