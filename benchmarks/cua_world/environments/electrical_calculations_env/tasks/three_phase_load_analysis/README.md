# Three-Phase Feeder Load Analysis

## Domain Context

Power quality engineers and industrial electricians routinely perform power audits on 3-phase distribution feeders to assess energy efficiency, identify penalty-triggering power factor conditions, and size compensation equipment. A complete power audit requires documenting all three power components: apparent power (S, in VA), real/true power (P, in W), and reactive power (Q, in VAR). These three values form the power triangle and must be internally consistent.

## Task Goal

You are a power quality engineer at a manufacturing plant. Your clamp meter measurements on a 3-phase, 400 V (line-to-line) distribution feeder show:
- Line voltage: 400 V
- Line current: 24 A
- Power factor: 0.80 lagging

You must use the Electrical Calculations app to compute and document all three power components for the power audit report.

## What Success Looks Like

The agent has successfully completed this task when:
1. The three-phase apparent power (S ≈ 16,627 VA) has been calculated
2. The three-phase real/true power (P ≈ 13,302 W) has been calculated
3. The three-phase reactive power (Q ≈ 9,976 VAR) has been calculated
4. The final screen shows the reactive power calculation result

The agent must independently discover that the app has separate calculators for each power component under the three-phase calculations section, and chain these calculations together.

## Calculations

- Apparent Power: S = √3 × V_L × I_L = 1.732 × 400 × 24 = 16,627.2 VA
- Real Power: P = S × PF = 16,627.2 × 0.80 = 13,301.8 W
- Reactive Power: Q = S × sin(arccos(PF)) = 16,627.2 × sin(arccos(0.80)) = 16,627.2 × 0.60 = 9,976.3 VAR
  - Note: sin(arccos(0.80)) = 0.60 exactly (3-4-5 right triangle)

## Verification Strategy

The verifier:
1. Parses the final UI dump XML to extract all displayed text/numbers
2. Checks if the reactive power result (≈9,976 VAR, ±3%) appears in the final screen
3. Awards partial credit for each power component that appeared during the calculation workflow
4. Awards bonus for being on the correct three-phase reactive power calculator at the end

## Scoring (100 points)

- Reactive power result on screen (≈9,976 VAR ±3%): 35 points [MANDATORY for pass]
- Real power result visible (≈13,302 W ±3%): 20 points
- Apparent power result visible (≈16,627 VA ±3%): 20 points
- Final screen is a three-phase power calculator: 15 points
- Any three-phase calculation visible in final UI dump: 10 points

Pass threshold: 60 points

## Why This Is Hard

- The app has dozens of calculators; the agent must navigate to the three-phase section
- Three distinct calculators must be used (apparent, real, reactive) — none are named in the description
- The agent must understand which formula applies to each calculator
- The inputs (400V, 24A, 0.80 PF) must be entered correctly in each calculator
- The agent must understand that sin(arccos(PF)) = √(1-PF²) for the reactive power
