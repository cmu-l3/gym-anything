# Task: crizotinib_concurrent_comedication_screening

## Domain Context

**Occupation**: Clinical Researcher
**Industry**: Pharmaceutical Industry / Drug Safety / Oncology Pharmacovigilance
**Environment**: Liverpool Cancer iChart Archive (Android app, `com.liverpooluni.ichartoncology`)

Clinical researchers in pharmaceutical pharmacovigilance teams compile drug interaction profiles for regulatory dossiers. When a cancer drug like crizotinib (ALK/ROS1/MET inhibitor for NSCLC) is used in real-world practice, patients frequently co-receive multiple co-medications simultaneously rather than one at a time. Documenting the concurrent interaction profile — how two or more co-medications interact with the cancer drug simultaneously on the same results screen — is a distinct workflow from sequential single-drug queries. The Liverpool Cancer iChart app supports multi-select co-medication queries, allowing both interactions to be displayed on the same Results screen for side-by-side comparison.

## Goal

You are compiling a pharmacovigilance dossier for crizotinib's real-world interaction profile. Two co-medications that frequently co-occur in the elderly NSCLC patient population must be documented together:

- **Acenocoumarol** — used for atrial fibrillation management in elderly lung cancer patients
- **Fluconazole** — used for antifungal prophylaxis in immunocompromised patients during chemotherapy

Using the Liverpool Cancer iChart Archive app, perform a **single combined interaction query**: select crizotinib as the cancer drug, then select **both acenocoumarol and fluconazole simultaneously** as co-medications in the same query before submitting. The Results screen should display both interaction ratings for crizotinib simultaneously. Remain on the Results screen showing both concurrent interaction results when finished.

## Success Criteria

The task is considered complete when:
1. Crizotinib is visible on the Results screen
2. **Both** acenocoumarol **and** fluconazole are visible simultaneously on the same Results screen
3. At least one interaction severity indicator is visible on the screen

## Key Feature Being Tested

This task specifically tests the app's **multi-select co-medication** feature — the agent must select two co-medications in a single query session rather than performing two separate single-drug queries. This requires discovering and using the multi-select capability of the app's co-medication selection screen.

## Verification Strategy

**Export pipeline**: `export_result.sh` runs `uiautomator dump`, greps the XML for crizotinib, acenocoumarol, fluconazole, and severity indicators, writes `/sdcard/crizotinib_concurrent_result.json`.

**Verifier scoring** (`verifier.py::verify_crizotinib_concurrent_comedication_screening`):

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| Gate 1 (identity) | 0 or fail | Crizotinib visible on screen |
| Gate 2 (co-med presence) | 0 or 5 | At least one co-med visible |
| Crizotinib visible | +20 | Crizotinib text on Results screen |
| Acenocoumarol visible | +20 | Acenocoumarol on screen |
| Fluconazole visible | +20 | Fluconazole on screen |
| Both co-meds simultaneously | +20 | Both acenocoumarol AND fluconazole present together |
| Severity indicator visible | +20 | Any interaction severity text present |
| **Pass threshold** | **≥ 75** | |

## Difficulty Justification

**Very Hard**: The agent must:
1. Navigate to the app's drug selection workflow without UI guidance
2. Select crizotinib as the cancer drug
3. **Discover** the multi-select co-medication feature (not obvious from standard single-select workflow)
4. Select both acenocoumarol and fluconazole without submitting between them
5. Submit the combined query and remain on the Results screen
6. This tests feature discovery and non-standard app workflow usage

## Contrast with Other Tasks

Tasks 1–4 all end on the **Interaction Details** page (deep navigation after selecting a single co-medication). Task 5 ends on the **Results page** (breadth — two co-medications shown simultaneously). This tests a fundamentally different feature of the app (multi-select workflow vs. single-select + drill-down).

## Technical Notes

- **App package**: `com.liverpooluni.ichartoncology`
- **Result JSON**: `/sdcard/crizotinib_concurrent_result.json`
- **XML dump**: `/sdcard/crizotinib_concurrent_dump.xml`
- **Environment**: Android AVD 34, 1080×2400 resolution
- All scripts use `#!/system/bin/sh` (POSIX sh, not bash)
- Do-nothing baseline: app is on Welcome screen → no drug names visible → all flags false → score=0

## Evidence

Evidence files are stored in `examples/liverpool_cancer_ichart_env/evidence_docs/`:
- `crizotinib_concurrent_comedication_screening_evidence.json`
