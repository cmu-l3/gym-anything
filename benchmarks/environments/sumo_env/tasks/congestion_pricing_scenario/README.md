# Task: congestion_pricing_scenario

## Occupation Context
**Role:** Economists (19-3011.00)
**Industry:** Government and Public Administration

## Task Description
A transport economist must evaluate a congestion pricing policy for the Bologna Pasubio corridor. The agent must run baseline and pricing-scenario simulations, model demand reduction from the charge (removing 15-25% of private vehicles whose routes traverse the charging zone while preserving bus services), compute network performance metrics, produce a monetized cost-benefit analysis using standard European transport economic values, and write an executive policy brief.

## Difficulty: very_hard
- Agent must understand SUMO route files and identify vehicles traversing a charging zone
- Must selectively remove private vehicles while preserving buses (route-level filtering)
- Must compute transport economics metrics (VKT, fuel consumption, emissions)
- Must apply standard economic values (Value of Time, fuel cost, CO2 social cost) for CBA
- Must produce monetized cost-benefit analysis with specific economic categories
- Must write professional policy brief with implementation recommendations
- Requires domain knowledge in both traffic simulation AND transport economics
- No UI path provided -- goal only

## Verification Criteria (100 points)
1. C1 (15 pts): Baseline simulation ran and traffic economics CSV produced
2. C2 (20 pts): Priced route file with 15-25% demand reduction, buses preserved
3. C3 (10 pts): Pricing sumocfg created and simulation ran
4. C4 (15 pts): Pricing scenario economics CSV with valid data
5. C5 (25 pts): CBA report CSV with monetized values for required categories
6. C6 (15 pts): Executive policy brief with economic analysis and recommendations

## Data / Scenario
- Scenario: `/home/ga/SUMO_Scenarios/bologna_pasubio/`
- Vehicle types: passenger1-5 (private), ignoring1-5 (private), bus (transit)
- Initial vehicle data saved to `/tmp/congestion_pricing_scenario_initial_data.json`
