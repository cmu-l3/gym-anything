# Task: Medication Allergy Reconciliation

## Domain Context

Medication allergy reconciliation is a critical patient safety workflow in hospital pharmacies and clinical settings. When a patient presents with a newly identified drug allergy, the clinical team must: document the allergy in the medical record, review current medication orders for contraindicated drugs, discontinue any offending medications, and prescribe safe alternatives. In East African district hospitals using Bahmni, this involves navigating the allergy module, the medication ordering system, and the clinical documentation features — all as part of a single patient encounter. This is a core competency for clinical officers, nurses, and pharmacists.

## Goal

Perform complete medication reconciliation for Aisha Abdullahi (BAH000008) who presented with a Penicillin allergy. By end of task, the system must reflect:

1. **Penicillin allergy documented** — recorded in her allergy list with severity and reaction details
2. **Penicillin V drug order discontinued** — the pre-seeded Penicillin V prescription is voided or stopped
3. **Safe alternative antibiotic prescribed** — a non-penicillin antibiotic drug order created (e.g., Azithromycin, Erythromycin, Doxycycline, Cotrimoxazole)
4. **Clinical encounter note written** — documenting the allergy discovery and medication changes (≥100 chars)

## Success Criteria

| Criterion | Points | Verifier Check |
|-----------|--------|----------------|
| Penicillin allergy documented | 30 | OpenMRS allergy API: patient/{uuid}/allergy |
| Penicillin V order discontinued/voided | 20 | Order status = DISCONTINUED or voided=true |
| Safe alternative antibiotic prescribed | 30 | New drug order for non-penicillin antibiotic |
| Clinical note documenting changes (≥100 chars) | 20 | Text obs in encounter |
| **Pass threshold** | **70** | Score ≥ 70 |

## Verification Strategy

1. `setup_task.sh` creates a visit for Aisha and seeds 3 drug orders: Penicillin V (active), Paracetamol (active), Ferrous Sulfate (active). Records baseline state.

2. `export_result.sh` queries:
   - Allergy list via `/patient/{uuid}/allergy`
   - All drug orders with their voided/stopped status
   - New orders created after task start
   - Any clinical note observations

3. `verifier.py` checks:
   - FIRST: patient is BAH000008 (wrong patient = score 0)
   - Penicillin entry in allergy list
   - Original Penicillin V order status
   - New non-penicillin antibiotic order
   - Clinical note length

## Schema Reference

- REST: `/openmrs/ws/rest/v1/patient/{uuid}/allergy`
- REST: `/openmrs/ws/rest/v1/order?patient={uuid}&t=drugorder&v=full`
- MySQL: `orders` table — `voided`, `date_stopped`, `order_action`
- MySQL: `allergy` table — `allergen_coded`, `severity`, `reactions`

## Starting State

Aisha Abdullahi (BAH000008) exists with:
- An active visit seeded by setup_task.sh
- Three drug orders: Penicillin V 250mg (active), Paracetamol 500mg (active), Ferrous Sulfate 200mg (active)
- No allergies recorded yet
- Baseline drug order count saved to `/tmp/mar_initial_order_count`

## Edge Cases

- Agent must navigate to Aisha's specific record (not another patient)
- The Penicillin allergy section is in a different area than the prescriptions module
- Agent must correctly identify Penicillin V as the problematic drug among three seeded orders
- Safe alternatives: Azithromycin, Erythromycin, Doxycycline, Cotrimoxazole, Ciprofloxacin, Clindamycin are all accepted
- Cross-reactive beta-lactams (Amoxicillin, Ampicillin, Cephalexin) are NOT accepted as safe alternatives
