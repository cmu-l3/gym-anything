# Bike Component Service Tracker Task

**Difficulty**: 🟢 Easy  
**Skills**: SUM function, cumulative metrics, cell references, arithmetic formulas  
**Duration**: 180 seconds  
**Steps**: ~10

## Objective

Create a bike maintenance tracking system that calculates cumulative mileage from ride logs and determines when components need service. This task tests cumulative calculations, reference tables, and predictive arithmetic.

## Task Description

Alex is an avid cyclist who learned the hard way that missing maintenance intervals is expensive. After riding 200 km past a chain service interval, the worn chain damaged the cassette, turning a $25 chain replacement into a $300 repair. Now Alex wants automated formulas to track when service is due.

The agent must:
1. Calculate total cumulative mileage from individual ride entries
2. Reference component service intervals from a lookup table
3. Calculate miles remaining until each component needs service
4. Use proper absolute/relative cell references for formula reusability

## Spreadsheet Structure

### Section 1: Ride Log (A1:B11)
- Column A: Ride dates
- Column B: Distance in km for each ride
- 10 rides logged (totaling ~385 km)

### Section 2: Service Intervals (D1:E7)
- Column D: Component names (Chain, Tires, Brake Pads, Full Tune-up)
- Column E: Service interval distances in km

### Section 3: Service Tracker (G1:I7)
- Column G: Component names (pre-filled)
- Column H: Service interval (agent enters formulas)
- Column I: Miles remaining (agent enters formulas)
- Row 2: Total mileage calculation

## Required Formulas

**Total Cumulative Mileage (H2):**