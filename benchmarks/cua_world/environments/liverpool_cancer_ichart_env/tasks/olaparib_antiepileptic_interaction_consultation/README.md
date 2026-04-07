# Task: olaparib_antiepileptic_interaction_consultation

## Domain Context

**Occupation**: Oncology Nurse Practitioner
**Industry**: Gynaecological Oncology
**Environment**: Liverpool Cancer iChart Archive (Android app, `com.liverpooluni.ichartoncology`)

Oncology nurse practitioners (ONPs) in gynaecological oncology manage patients on PARP inhibitor maintenance therapy, including olaparib, after platinum-based chemotherapy for BRCA-mutated ovarian cancers. When a patient on olaparib has a comorbidity requiring a new co-medication from another specialty, the ONP must assess for drug interactions before the co-medication is initiated. Olaparib is a CYP3A4 substrate: co-administration with strong CYP3A4 inducers (such as enzyme-inducing antiepileptics) dramatically reduces olaparib AUC, risking loss of maintenance efficacy. The interaction is so significant that the olaparib Summary of Product Characteristics (SmPC) lists strong CYP3A4 inducers as contraindicated.

## Goal

A patient with BRCA1-mutated high-grade serous ovarian cancer is on olaparib maintenance therapy following platinum-based chemotherapy. She has a pre-existing diagnosis of partial epilepsy. The neurology team has asked for advice on three medication options in the context of the olaparib therapy:

- **Carbamazepine** — enzyme-inducing antiepileptic being considered for partial seizure control
- **Warfarin** — included by neurology for anticoagulation co-management of DVT
- **Acenocoumarol** — included by haematology for anticoagulation

Using the Liverpool Cancer iChart Archive app, look up the interaction rating for each of these three co-medications against olaparib. Then navigate to and remain on the **Interaction Details** screen specifically for olaparib's interaction with carbamazepine, which is the antiepileptic being considered for initiation.

## Success Criteria

The task is considered complete when:
1. The agent is on the **Interaction Details** screen for **Olaparib + Carbamazepine**
2. The severity indicator is visible (expected: red/Do Not Coadminister or strong warning)
3. CYP3A4 induction/AUC/exposure mechanism text is visible in the details

## Why Carbamazepine Is the Target

- **Carbamazepine**: Strong CYP3A4 inducer → reduces olaparib AUC by ~87% → contraindicated → **Do Not Coadminister (Red)**
- **Warfarin**: No major pharmacokinetic interaction with olaparib (different metabolic pathway)
- **Acenocoumarol**: Similar to warfarin; not a CYP3A4 modulator

The task explicitly specifies carbamazepine as "the antiepileptic drug being considered for initiation" and asks the agent to navigate to its specific Interaction Details screen.

## Verification Strategy

**Export pipeline**: `export_result.sh` runs `uiautomator dump`, greps the XML for drug names, severity text, and mechanism keywords (cyp3a4, induc, auc, exposure, plasma), writes `/sdcard/olaparib_antiepileptic_result.json`.

**Verifier scoring** (`verifier.py::verify_olaparib_antiepileptic_interaction_consultation`):

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| Gate 1 (identity) | 0 or fail | Olaparib visible on screen |
| Gate 2 (target) | 0 or 5 | Carbamazepine visible (not wrong co-med) |
| Drug pair on screen | +20 | Both olaparib and carbamazepine visible |
| Severity indicator | +20 | "Do Not Coadminister" text visible |
| Interaction Details page | +35 | "Interaction Details" text visible |
| Mechanism text | +25 | CYP3A4/induc/AUC/exposure/plasma text visible |
| **Pass threshold** | **≥ 70** | |

## Difficulty Justification

**Very Hard**: The agent must:
1. Navigate the app's interaction search workflow without UI guidance
2. Screen three co-medications against olaparib
3. Navigate to the specific Interaction Details page for olaparib + carbamazepine
4. Remain on the correct screen (not the Results overview page)
5. The task involves distinguishing between anticoagulants (warfarin, acenocoumarol) and antiepileptics (carbamazepine) in a complex clinical referral scenario

## Technical Notes

- **App package**: `com.liverpooluni.ichartoncology`
- **Result JSON**: `/sdcard/olaparib_antiepileptic_result.json`
- **XML dump**: `/sdcard/olaparib_antiepileptic_dump.xml`
- **Environment**: Android AVD 34, 1080×2400 resolution
- All scripts use `#!/system/bin/sh` (POSIX sh, not bash)
- Do-nothing baseline: app is on Welcome screen → all flags false → score=0

## Evidence

Evidence files are stored in `examples/liverpool_cancer_ichart_env/evidence_docs/`:
- `olaparib_antiepileptic_interaction_consultation_evidence.json`
