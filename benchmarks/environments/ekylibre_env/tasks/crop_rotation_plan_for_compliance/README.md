# Task: crop_rotation_plan_for_compliance

## Overview

**Difficulty**: Very Hard
**Role**: Farm Manager / Agricultural Manager
**Domain**: EU CAP Subsidy Compliance — Crop Rotation Planning
**Environment**: Ekylibre FMIS (French farm management system), GAEC JOULIN demo data

## Background

The EU Common Agricultural Policy (CAP) requires French farms receiving direct payments to demonstrate crop diversification and rotation compliance under the "éco-régimes" and BCAE (Bonnes Conditions Agricoles et Environnementales) standards. A farm receiving more than €60,000/year in CAP payments must cultivate at least 3 different crops, with the main crop covering no more than 65% of arable area and the two main crops together no more than 90%.

GAEC JOULIN is a mixed farm that needs to document its 2024 rotation plan in Ekylibre for submission to the DDT (Direction Départementale des Territoires).

## Goal

The agent must:
1. Investigate the 2023 crop activity productions to understand the current parcel-crop mapping
2. Identify land parcels available for 2024 planning
3. Create activity productions for ≥3 parcels in the 2024 campaign, using ≥2 different crop activity types
4. Follow rotation logic: cereal parcels should rotate to oilseeds or legumes
5. Set realistic growing season dates for 2024

## Success Criteria

- **Criterion 1** (30 pts): ≥3 new activity_productions created after task start
- **Criterion 2** (25 pts): Productions belong to a 2024 campaign (started_on year = 2024)
- **Criterion 3** (25 pts): ≥2 distinct activity types used across the new productions
- **Criterion 4** (20 pts): Each production has a valid support (land parcel) assigned

**Pass threshold**: ≥60 points
**Mandatory**: At least 1 new activity_production created

## Verification Strategy

The export script queries:
- `activity_productions` table for records created after task_start
- `campaigns` table to verify year of associated campaign
- `activities` table to verify distinct activity types

## What the Agent Must Discover

- Which modules contain activity productions (Productions végétales or Production > Cultures)
- How to navigate to and create activity productions
- Which land parcels exist and are available
- Which crop activities are defined in the system
- Which existing 2023 parcels need rotation

## Schema Reference

```sql
-- Key tables (demo schema in ekylibre_production)
SET search_path TO demo, lexicon, public;

SELECT id, activity_id, campaign_id, support_id, started_on, stopped_on
FROM activity_productions
ORDER BY id DESC LIMIT 20;

SELECT id, name, started_on, stopped_on FROM campaigns ORDER BY started_on;

SELECT id, name, family FROM activities;

SELECT id, name FROM land_parcels LIMIT 20;
```

## Notes

- The GAEC JOULIN demo data contains real land parcels (ZC#01, ZC#02, ZC#06, etc.)
- Activities include Blé tendre d'hiver (soft winter wheat), Colza (rapeseed), etc.
- Campaign 2023 has ID=8 in the demo data
- The agent should create/find the 2024 campaign if it doesn't exist
