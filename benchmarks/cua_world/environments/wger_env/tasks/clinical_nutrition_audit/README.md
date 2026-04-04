# Clinical Nutrition Audit

## Occupation Context
**Registered Dietitian** (SOC 29-2051.00) — Healthcare Practitioners and Technical

Registered dietitians conduct periodic clinical audits of patient nutrition plans to ensure energy targets align with evidence-based guidelines (AHA, ADA, ASMBS). This task simulates a quarterly audit where multiple nutrition plans have drifted from clinically recommended values and the dietitian must correct them, create new clinical measurement tracking categories, and set up a new patient plan.

## Task Overview
The agent must read a clinical audit report placed on the desktop, then:
1. Correct the daily energy (kcal) goals for 3 existing nutrition plans to match clinical guidelines
2. Create 2 new measurement tracking categories for clinical monitoring
3. Create a new nutrition plan for an additional patient

## Starting State
- 3 nutrition plans exist with WRONG energy goals (set by setup_task.sh)
- An audit report at `/home/ga/Documents/nutrition_audit_report.txt` specifies the correct values
- Firefox is open to the nutrition overview page

## Verification Strategy
- **C1-C3**: Check each plan's energy goal matches the clinically correct value (1800, 2100, 1400 kcal)
- **C4-C5**: Check that measurement categories exist with correct units
- **C6**: Check that the new nutrition plan exists

## Features Exercised
- Nutrition plan energy goal editing
- Measurement category creation
- Nutrition plan creation
- Companion document reading
- Multi-plan navigation
