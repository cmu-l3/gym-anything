# Task: courier_urban_delivery

## Summary

Configure Sygic GPS Navigation for an urban delivery van driver at FastPack Urban Deliveries. The dispatcher must set up the driver's work phone with the correct vehicle profile, route type, toll avoidance, measurement units, and street-side arrival mode.

## Occupation Context

**Primary occupation**: Driver/Sales Workers and Couriers
**GDP relevance**: $102M+ economic output; urban delivery is one of the highest-frequency GPS use cases

## Scenario

FastPack Urban Deliveries operates a fleet of compact delivery vans making 30–40 stops per day in the city center. A new driver is starting their first shift and their GPS must be configured to company spec:

- **Vehicle profile**: Delivery van (not a passenger car). Name: "City Courier Van", diesel, 2021, Euro 6.
- **Route type**: Shortest distance (fuel cost optimization for salaried drivers).
- **Toll avoidance**: On — tolls are not reimbursed for local urban routes.
- **Distance units**: Kilometers (company operates on metric).
- **Arrive-in-direction**: On — drivers must pull up on the correct sidewalk side for handoffs.

## Difficulty: very_hard

The task description provides professional context only — no UI navigation steps, no explicit setting names. The agent must deduce which Sygic settings correspond to each business requirement.

## Verification

Scoring (100 pts, pass=65):
| Criterion | Points |
|-----------|--------|
| Van profile name contains 'courier', 'city', or 'van' | 20 |
| Vehicle type = VAN | 15 |
| Fuel=DIESEL, Year=2021, Emission=EURO6 | 15 |
| Van profile is active | 15 |
| Route compute = Shortest | 15 |
| Toll roads avoided | 10 |
| Distance units = Km | 5 |
| Arrive-in-direction enabled | 5 |

## Files

- `task.json` — task spec and metadata
- `setup_task.sh` — resets to known starting state (fastest route, no toll avoidance, miles, arrive-off)
- `export_result.sh` — force-stops app, reads vehicle DB + prefs XML, writes JSON
- `verifier.py` — multi-criterion scoring with gate check
- `README.md` — this file

## Setup Starting State

| Setting | Start Value | Target Value |
|---------|-------------|--------------|
| Extra vehicle profiles | none (only Vehicle 1) | City Courier Van added |
| Route compute | Fastest (1) | Shortest (0) |
| Toll road avoidance | false | true |
| Distance units | Miles (0) | Km (1) |
| Arrive-in-direction | false | true |
