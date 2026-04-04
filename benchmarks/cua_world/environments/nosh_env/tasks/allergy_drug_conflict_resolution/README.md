# allergy_drug_conflict_resolution

## Overview

**Difficulty**: very_hard
**Environment**: NOSH ChartingSystem (nosh_env@0.1)
**Occupation context**: Sports Medicine Physician / Registered Nurse conducting a medication safety review
**Features tested**: Allergies, Rx (medications — both deactivation and new prescribing), Encounters

## Domain Context

Medication safety audits are a critical patient safety practice. Staff review each patient's allergy documentation alongside their active medication list to detect contraindications. When a conflict is found, the offending medication must be discontinued and a safe alternative prescribed. This task requires clinical domain knowledge to recognize which drug-allergy combinations constitute genuine contraindications.

## Goal

The agent must (without being told which patients have conflicts):

1. **Review** each patient's allergy list and active medication list
2. **Identify** the 3 patients with genuine allergy-drug conflicts
3. **Discontinue** the contraindicated medication for each patient
4. **Prescribe** a safe alternative medication
5. **Document** the intervention with an encounter note

One patient has a documented allergy but no conflict with their current medication (noise — do NOT modify their prescription).

## Starting State (seeded by setup_task.sh)

| PID | Name | Allergy | Current Rx | Conflict? |
|-----|------|---------|-----------|-----------|
| 32 | Marcus Odom | Sulfonamides | Trimethoprim-Sulfamethoxazole (TMP-SMX) | **YES** — TMP-SMX contains sulfonamide |
| 33 | Patricia Fenn | Penicillin | Amoxicillin | **YES** — Amoxicillin is penicillin-class |
| 34 | Theodore Ashe | Codeine | Codeine Phosphate | **YES** — Direct allergen match |
| 35 | Nancy Briggs | Latex | Metformin | No (latex allergy ≠ Metformin contraindication) |

## Success Criteria

The task is complete when:
1. Conflicting medication is discontinued (inactive) for pids 32, 33, 34
2. A safe alternative is prescribed for each
3. At least 2 encounter notes document the changes

## Verification Strategy

**Export script** (`export_result.sh`) queries:
- Active rx count before vs. after for each conflict patient
- Whether specific conflicting drugs are now inactive (rxl_active='n') or deleted
- Whether any new active rx exists that doesn't contain the allergen
- Encounter counts before vs. after

**Verifier** (`verifier.py::verify_allergy_drug_conflict_resolution`) scores:
| Criterion | Points |
|-----------|--------|
| TMP-SMX discontinued for Marcus Odom (pid 32) | 20 |
| Safe alternative prescribed for pid 32 | 10 |
| Amoxicillin discontinued for Patricia Fenn (pid 33) | 20 |
| Safe alternative prescribed for pid 33 | 10 |
| Codeine Phosphate discontinued for Theodore Ashe (pid 34) | 20 |
| Safe alternative prescribed for pid 34 | 10 |
| Encounter notes created (≥2 patients) | 10 |
| **Total** | **100** |
| **Pass threshold** | **60** |

## Partial Credit Structure

- Prescriptions: binary (discontinued or not, alternative or not)
- Max partial: 3 discontinued + 0 alternatives + 0 encounters = 60 pts → passes
- This is intentional: if an agent finds and discontinues all 3 conflicts, that is clinically significant

Max partial score (all discontinuations, no alternatives, no encounters) = 60 pts. This exactly meets threshold. ✓ (The agent must discover the conflicts to discontinue; it can't accidentally score 60 without doing meaningful work.)

## Relevant Database Tables

```sql
-- Check allergies per patient
SELECT pid, allergen, allergy_type, allergy_reaction FROM allergies WHERE pid IN (32,33,34,35);

-- Check active medications
SELECT pid, drug_name, rxl_dosage, rxl_active FROM rx WHERE pid IN (32,33,34,35);

-- Check encounters
SELECT pid, encounter_date, reason FROM encounters WHERE pid IN (32,33,34,35);
```

## Clinical Knowledge Required

To solve this task, the agent must know:
- **Sulfonamide allergy** contraindicates: TMP-SMX, sulfadiazine, sulfasalazine, furosemide (sulfa-containing)
- **Penicillin allergy** contraindicates: amoxicillin, ampicillin, nafcillin, piperacillin (penicillin-class antibiotics)
- **Codeine allergy** contraindicates: codeine, codeine phosphate, any codeine-containing compound

Alternative agents (any domain-valid alternative accepted by verifier):
- For pid 32: Ciprofloxacin, Nitrofurantoin, Doxycycline, Fosfomycin
- For pid 33: Azithromycin, Doxycycline, Clindamycin, Clarithromycin
- For pid 34: Tramadol, Ibuprofen, Naproxen, Acetaminophen, Oxycodone

## Edge Cases

- **Agent deletes rather than deactivates**: Verifier detects both inactivation (rxl_active='n') and removal
- **Agent adds alternative with allergen in name**: Verifier filters out penicillin/sulfa/codeine-containing drugs from the "alternative" query
- **Agent modifies noise patient**: Metformin active status tracked but not scored
