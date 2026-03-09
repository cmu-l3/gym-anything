# Motor Cable Sizing Calculation

## Domain Context

Sizing supply cables for electric motors is one of the most common tasks an electrician performs. It requires chaining two types of calculations:
1. **Motor current** from nameplate data: The motor nameplate gives rated *output* power; the electrician must account for both efficiency (to get input power) and power factor (to get the actual line current).
2. **Cable sizing**: Given the current, cable length, and voltage drop limit, select the minimum conductor cross-section.

This is a real-world task because neither the current nor the cable size is directly readable from the motor nameplate — both require calculation.

## Task Goal

**Motor**:
- Rated output: 3.7 kW
- Efficiency: 88%
- Power factor: 0.85
- Supply voltage: 240 V single-phase

**Installation**:
- Cable length: 35 metres
- Max voltage drop: 5%

**Required**:
1. Calculate the motor's input power: P_input = P_output / η = 3700 / 0.88 = 4204.5 W
2. Calculate the motor's line current: I = P_input / (V × PF) = 4204.5 / (240 × 0.85) = 20.61 A
3. Use the cable size calculator with I = 20.61 A, V = 240 V, L = 35 m, PF = 0.85, VD = 5%

## What Success Looks Like

The agent has successfully completed this task when:
1. The motor current (~20.61 A) has been calculated and verified using the single-phase current calculator
2. The cable size calculator has been used with the calculated current and given parameters
3. The final screen shows a cable size result (the exact size depends on the app's conductor database)

## Calculations

- Motor input power: P_in = 3700 / 0.88 = 4204.5 W
- Motor line current: I = P_in / (V × PF) = 4204.5 / (240 × 0.85) = 4204.5 / 204 = 20.61 A
- Cable size: depends on app's cable database for the given parameters

## Verification Strategy

The verifier checks for:
1. The correct motor current (≈20.61 A ±3%) visible on screen — this means the agent correctly
   accounted for both efficiency and power factor
2. Cable size calculator keywords visible
3. Cable size result visible (any valid AWG or mm² value)
4. Task parameters (240V / 35m / 5%) visible

## Scoring (100 points)

- Motor current on screen (≈20.61 A ±3%):              40 pts [MANDATORY for pass]
- Cable size calculator is shown:                       20 pts
- A cable size result is visible on screen:             20 pts
- Cable sizing parameters (240V / 35m) visible:         10 pts
- Power factor (0.85) or input power visible:           10 pts

Pass threshold: 60 points (motor current required)

## Why This Is Hard

- The agent must understand that motor nameplate output ≠ input power
- Two separate calculations must be chained: current calculation → cable size
- The agent must navigate from power/current calculators to cable calculators
- Must correctly apply both efficiency AND power factor in the current calculation
- The task does not reveal which calculators to use
