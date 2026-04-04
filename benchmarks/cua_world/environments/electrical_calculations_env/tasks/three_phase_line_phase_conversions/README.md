# Three-Phase Line-to-Phase Conversions

## Domain Context

Understanding the relationship between line quantities (measured between conductors) and phase quantities (across individual windings) is fundamental to 3-phase electrical engineering. For wye (star) connections: V_phase = V_line / √3 and I_phase = I_line. For delta connections: V_phase = V_line and I_phase = I_line / √3. Electricians need these conversions when selecting motor windings, sizing contactors, and verifying protection settings for motor control centres.

## Task Goal

**Supply**: 415 V line-to-line, 63 A line current

**Required calculations**:
1. **Wye phase voltage**: V_phase = V_line / √3 = 415 / √3 = 239.6 V
   (What voltage each winding sees in a star-connected load)
2. **Delta phase current**: I_phase = I_line / √3 = 63 / √3 = 36.37 A
   (What current flows through each winding in a delta-connected load)

## What Success Looks Like

The agent has successfully completed this task when:
1. The wye phase voltage (≈239.6 V) has been calculated using the line-to-phase voltage conversion
2. The delta phase current (≈36.37 A) has been calculated using the line-to-phase current conversion
3. The final screen shows one of these conversion results

## Calculations

- Phase voltage (wye):   V_phase = V_line / √3 = 415 / 1.732 = 239.6 V
- Phase current (delta): I_phase = I_line / √3 = 63  / 1.732 = 36.37 A

Note: √3 ≈ 1.732

## Verification Strategy

The verifier checks the final UI dump for both conversion results.
The phase current (36.37 A) is the more discriminating check because the agent
must use the line-to-phase current conversion calculator specifically.

## Scoring (100 points)

- Delta phase current (≈36.37 A ±3%):                  35 pts [MANDATORY for pass]
- Wye phase voltage (≈239.6 V ±3%):                    30 pts
- Line/phase conversion calculator keywords visible:     20 pts
- Input values (415V / 63A) visible:                    15 pts

Pass threshold: 60 points (phase current result required)

## Why This Is Hard

- The agent must find the line-to-phase conversion calculators (separate for voltage and current)
- Must understand that wye and delta follow different conversion rules
- Two conversion calculators must be used in sequence
- The task does not name which calculator to use
- The agent must know: for wye, V_ph = V_L/√3; for delta, I_ph = I_L/√3
