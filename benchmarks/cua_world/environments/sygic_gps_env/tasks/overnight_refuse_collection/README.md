# Task: overnight_refuse_collection

## Summary

Configure Sygic GPS Navigation for a municipal refuse collection truck operating an overnight 2 AM–6 AM route. The dispatcher must set up the driver's device with a truck profile, night display mode, highway avoidance, shortest-distance routing, and Fahrenheit temperature units.

## Occupation Context

**Primary occupation**: Refuse and Recyclable Material Collectors
**GDP relevance**: $21M economic output; municipal GPS is a core operational tool for overnight route management

## Scenario

Riverside Municipal Waste Services runs overnight routes to avoid daytime traffic. Requirements:

- **Night display**: Dark theme mandatory — bright screen blinds drivers in unlit cabs at 3 AM.
- **No highways**: Weight restrictions on highway overpasses prohibit refuse trucks from those corridors.
- **Shortest route**: Fuel-cost efficiency metric for municipal budget.
- **Vehicle profile**: Heavy refuse truck. Name: "Refuse Truck", diesel, 2018, Euro 6.
- **Temperature units**: Fahrenheit — the municipal maintenance shop uses US standard for repair logs.

## Difficulty: very_hard

Description gives only professional/operational context, no UI navigation steps or explicit setting names. The agent must map business requirements to Sygic settings.

## Verification

Scoring (100 pts, pass=65):
| Criterion | Points |
|-----------|--------|
| Truck profile name contains 'refuse', 'truck', or 'waste' | 20 |
| Vehicle type = TRUCK | 15 |
| Fuel=DIESEL, Year=2018, Emission=EURO6 | 15 |
| Truck profile is active | 15 |
| Route compute = Shortest | 15 |
| Highways avoided | 10 |
| App theme = Night | 5 |
| Temperature = Imperial | 5 |

## Setup Starting State

| Setting | Start Value | Target Value |
|---------|-------------|--------------|
| Extra vehicle profiles | none (only Vehicle 1) | Refuse Truck added |
| Route compute | Fastest (1) | Shortest (0) |
| Avoid highways | false | true |
| App theme | Auto (0) | Night (2) |
| Temperature units | Metric | Imperial |
