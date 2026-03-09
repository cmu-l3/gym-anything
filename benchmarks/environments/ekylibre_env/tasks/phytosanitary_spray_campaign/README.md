# Task: phytosanitary_spray_campaign

## Overview

**Difficulty**: Very Hard
**Role**: Crop Protection Manager / Agricultural Manager
**Domain**: Field Operations — Phytosanitary Intervention Recording
**Environment**: Ekylibre FMIS, GAEC JOULIN demo data

## Background

Under French agricultural law (Articles L. 253-1 to L. 253-17 of the Code rural), farmers must maintain a Registre Phytosanitaire (phytosanitary register) recording all plant protection product applications. This register must include:
- Date and location of treatment (field/parcel)
- Product name, batch number, and application dose
- Equipment used
- Operator name
- Reason for treatment (pest/disease)
- PHI (Pre-Harvest Interval) compliance

GAEC JOULIN has received an urgent alert for Fusarium head blight (fusariose) in wheat fields across Charente-Maritime (département 17). The disease typically appears in June (BBCH stage 65-69 = anthesis) and requires timely fungicide application.

## Goal

The agent must:
1. Find which parcels belong to the Blé tendre d'hiver activity in campaign 2023
2. For EACH wheat parcel, create a separate spraying intervention (Pulvérisation)
3. Each intervention must record: date 2023-06-15, product, dose, equipment, worker

## Success Criteria

- **Criterion 1** (35 pts): ≥3 new spraying interventions created after task start
- **Criterion 2** (25 pts): Interventions have a phytosanitary/spraying procedure type
- **Criterion 3** (25 pts): Interventions are dated 2023-06-15
- **Criterion 4** (15 pts): Interventions have worker or equipment parameters assigned

**Pass threshold**: 60 points
**Mandatory**: ≥2 new spraying-type interventions

## Verification Strategy

Export script queries:
- `interventions` for records with procedure_name matching spray/pulv patterns, created after task_start
- `intervention_parameters` for input products and tools
- Cross-references activity productions for wheat parcel list

## What the Agent Must Discover

- Which parcels are in the wheat activity (navigate Activities → Productions → supports)
- Which products are in the phytosanitary input catalog
- How to create an intervention for a specific parcel
- Which equipment and workers are available

## Schema Reference

```sql
SET search_path TO demo, lexicon, public;

-- Interventions and procedure names
SELECT id, number, procedure_name, started_at, state, created_at
FROM interventions ORDER BY id DESC LIMIT 20;

-- Activity productions for wheat (activity_id=3 = Blé tendre d'hiver)
SELECT id, activity_id, campaign_id, support_id, started_on
FROM activity_productions WHERE activity_id = 3;

-- Intervention parameters (inputs, targets, tools)
SELECT ip.id, ip.type, ip.intervention_id, ip.product_id
FROM intervention_parameters ip
WHERE ip.intervention_id IN (SELECT id FROM interventions ORDER BY id DESC LIMIT 5);

-- Available products (phytosanitary inputs)
SELECT id, name FROM product_natures WHERE id IN (
  SELECT product_nature_id FROM product_natures_variants
  WHERE name ILIKE '%fongicide%' OR name ILIKE '%fungicide%' OR name ILIKE '%traitement%'
) LIMIT 10;
```

## Notes

- GAEC JOULIN's 2023 spray interventions (Pulvérisation) covered ZC#01, ZC#02, ZC#06, ZC#07, ZC#10, ZC#19
- activity_id=3 = Blé tendre d'hiver, campaign_id=8 = 2023
- procedure_name for spraying in Ekylibre: "plant_watering" or "spraying" or custom
