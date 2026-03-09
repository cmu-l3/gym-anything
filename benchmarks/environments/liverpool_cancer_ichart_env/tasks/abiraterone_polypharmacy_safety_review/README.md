# Task: abiraterone_polypharmacy_safety_review

## Domain Context

**Occupation**: Medical Oncologist
**Industry**: Urology-Oncology / Prostate Cancer
**Environment**: Liverpool Cancer iChart Archive (Android app, `com.liverpooluni.ichartoncology`)

Medical oncologists managing metastatic castration-resistant prostate cancer (mCRPC) routinely initiate patients on abiraterone acetate, a CYP17A1 inhibitor that suppresses androgen synthesis. Elderly prostate cancer patients often carry significant comorbidities requiring multiple co-medications from other specialties. The oncologist must personally verify that none of the co-medications creates a dangerous drug interaction before initiating abiraterone. Ketoconazole is particularly problematic: it is itself a CYP17A1 inhibitor (the same enzyme abiraterone targets), creating an additive hormonal blockade, while also being a potent CYP3A4 inhibitor that affects abiraterone metabolism.

## Goal

A 78-year-old patient with metastatic castration-resistant prostate cancer is being initiated on abiraterone acetate. He has three active co-medications:

- **Ketoconazole** — prescribed by dermatology for resistant fungal skin infection
- **Warfarin** — prescribed by cardiology for mechanical heart valve prosthesis
- **Acenocoumarol** — newly prescribed by haematology for DVT treatment

Using the Liverpool Cancer iChart Archive app, screen all three co-medications against abiraterone to obtain their interaction ratings. After reviewing all three results, navigate to and remain on the **Interaction Details** screen for the co-medication carrying the most clinically significant contraindication with abiraterone.

## Success Criteria

The task is considered complete when:
1. The agent is on the **Interaction Details** screen for **Abiraterone + Ketoconazole**
2. The "Do Not Coadminister" severity indicator is visible
3. The CYP17A1 or CYP3A4 pharmacokinetic/pharmacodynamic mechanism text is visible

## Why Ketoconazole Is the Target

- **Ketoconazole**: Dual mechanism — (1) both drugs inhibit CYP17A1 (additive adrenal suppression), (2) potent CYP3A4 inhibitor increases abiraterone AUC → **Do Not Coadminister (Red)**
- **Warfarin**: Potential interaction via CYP2C9 inhibition (abiraterone may increase warfarin exposure) → monitoring required but not contraindicated
- **Acenocoumarol**: Similar anticoagulant class to warfarin, potential interaction but not the most severe

The agent must screen all three and identify ketoconazole as the most severely contraindicated.

## Verification Strategy

**Export pipeline**: `export_result.sh` runs `uiautomator dump`, greps the XML for drug names, severity text, and mechanism keywords, writes `/sdcard/abiraterone_safety_result.json`.

**Verifier scoring** (`verifier.py::verify_abiraterone_polypharmacy_safety_review`):

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| Gate 1 (identity) | 0 or fail | Abiraterone visible on screen |
| Gate 2 (target) | 0 or 5 | Ketoconazole visible (not wrong co-med) |
| Drug pair on screen | +20 | Both abiraterone and ketoconazole visible |
| Severity indicator | +25 | "Do Not Coadminister" text visible |
| Interaction Details page | +35 | "Interaction Details" text visible |
| Mechanism text | +20 | CYP17/CYP17A1/CYP3A4/androgen mechanism text |
| **Pass threshold** | **≥ 70** | |

## Difficulty Justification

**Very Hard**: The agent must:
1. Navigate to the app's interaction search workflow without UI guidance
2. Screen three co-medications against abiraterone
3. Identify the most severely contraindicated co-medication
4. Understand that ketoconazole is contraindicated not just due to PK interaction but dual pharmacological mechanism
5. Navigate from Results screen to the deeper Interaction Details view
6. Remain on the correct screen at task end

## Technical Notes

- **App package**: `com.liverpooluni.ichartoncology`
- **Result JSON**: `/sdcard/abiraterone_safety_result.json`
- **XML dump**: `/sdcard/abiraterone_safety_dump.xml`
- **Environment**: Android AVD 34, 1080×2400 resolution
- All scripts use `#!/system/bin/sh` (POSIX sh, not bash)
- Do-nothing baseline: app is on Welcome screen → all flags false → score=0

## Evidence

Evidence files are stored in `benchmarks/environments/liverpool_cancer_ichart_env/evidence/`:
- `abiraterone_polypharmacy_safety_review_evidence.json`
