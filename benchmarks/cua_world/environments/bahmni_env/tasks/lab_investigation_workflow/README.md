# Task: Lab Investigation Workflow (Fever/Malaria)

## Domain Context

Integrated clinical-laboratory workflows are central to the Bahmni HIS value proposition in resource-limited settings. When a patient presents with fever in a malaria-endemic region, the clinical officer must order labs, receive results, update the diagnosis, and prescribe treatment — all within the same electronic system. Bahmni's lab module (bahmni-lab) allows lab technicians to receive orders from clinicians and enter results that immediately update the clinical record. This mirrors the real workflow at Kenyan, Ethiopian, and Indian district hospitals where Bahmni is deployed. The task requires navigating across at least three Bahmni modules: clinical (for ordering and diagnosis), lab (for results entry), and pharmacy/medication orders.

## Goal

Complete a full clinical-lab-pharmacy cycle for Kofi Asante (BAH000024) presenting with fever and suspected malaria. By end of task:

1. **Clinical encounter created** — OPD consultation with history/complaint documented
2. **Lab orders placed** — at least CBC (Full Blood Count) and a malaria test ordered from the clinical module
3. **Lab results entered** — CBC results (hemoglobin + WBC) and malaria test result (positive) entered in the lab module
4. **Diagnosis updated and treatment prescribed** — Malaria diagnosis confirmed, antimalarial drug prescribed

## Success Criteria

| Criterion | Points | Verifier Check |
|-----------|--------|----------------|
| Clinical encounter with note/complaint created | 20 | Encounter with text obs (>=50 chars) |
| Lab orders placed (CBC + malaria test) | 25 | Test orders in OpenMRS (order type = lab/test) |
| Lab results entered (CBC + positive malaria) | 30 | OpenMRS obs for CBC concepts + malaria result |
| Antimalarial treatment prescribed | 25 | Drug order for recognized antimalarial |
| **Pass threshold** | **70** | Score ≥ 70 |

## Verification Strategy

1. `setup_task.sh` creates patient BAH000024 (Kofi Asante) with no prior history. Records baseline state.

2. `export_result.sh` queries:
   - All encounters for Kofi
   - All orders (test orders + drug orders)
   - All observations (lab results + clinical notes)
   - MySQL for specific lab result observations

3. `verifier.py` checks each criterion with wrong-target gate first.

## Schema Reference

CIEL concept UUIDs for CBC:
- Hemoglobin: `21AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- White Blood Cell Count: `678AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Platelet Count: `729AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- Malaria RDT result: `32AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA` or concept name "MALARIA SMEAR"

Order types:
- Test order (lab): `Lab Order` or `Test Order` encounter type
- Drug order: `DRUG_ORDER` concept class

Antimalarial drug keywords:
- artemether, lumefantrine, artesunate, quinine, chloroquine, primaquine,
  coartem, artequin, fansidar, mefloquine

## Starting State

- Kofi Asante (BAH000024) created in setup with no prior encounters/orders
- Browser opened to Bahmni login page
- Baseline state recorded (all counts = 0)

## Edge Cases

- Agent must navigate: Clinical module → order labs → navigate to Lab module → enter results → return to Clinical → update diagnosis → prescribe
- Bahmni lab module may be at a different URL path than the main clinical module
- Lab results module may require separate login or navigation step
- CBC concept names in Bahmni may differ from CIEL standard names
- Verifier uses broad keyword matching for lab concepts and drug names
- Malaria test may appear as "Malaria RDT", "Blood Film", "Malaria Smear", or "Thick Blood Film"
