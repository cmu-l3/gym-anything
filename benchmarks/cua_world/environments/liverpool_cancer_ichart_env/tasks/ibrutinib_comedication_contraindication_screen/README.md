# Task: ibrutinib_comedication_contraindication_screen

## Domain Context

**Occupation**: Oncology Clinical Pharmacist
**Industry**: Haematology Oncology
**Environment**: Liverpool Cancer iChart Archive (Android app, `com.liverpooluni.ichartoncology`)

Oncology clinical pharmacists in haematology centres are responsible for medication review and drug-drug interaction screening before cancer drug initiation. Ibrutinib (a Bruton's tyrosine kinase inhibitor) is a narrow-therapeutic-index agent predominantly metabolised by CYP3A4. Co-prescribing with CYP3A4 inhibitors can dramatically increase ibrutinib plasma exposure, raising the risk of serious toxicity including atrial fibrillation, bleeding, and cardiac arrhythmias. Before any patient is started on ibrutinib, every active co-medication must be screened for interactions.

## Goal

A 73-year-old patient with relapsed chronic lymphocytic leukaemia (CLL) is being initiated on ibrutinib. Three co-medications are prescribed by other specialists:

- **Acenocoumarol** — anticoagulant prescribed by cardiology
- **Fluconazole** — antifungal prescribed by infectious disease
- **Ketoconazole** — antifungal prescribed by dermatology

Using the Liverpool Cancer iChart Archive app, screen all three co-medications against ibrutinib to obtain their drug-drug interaction ratings. Identify the co-medication with the most severe interaction and navigate to the full **Interaction Details** screen for that specific drug pair, remaining on that screen when finished.

## Success Criteria

The task is considered complete when:
1. The agent is on the **Interaction Details** screen for **Ibrutinib + Ketoconazole**
2. The "Do Not Coadminister" severity indicator is visible (red interaction)
3. The CYP3A4 pharmacokinetic mechanism text is visible in the interaction details

## Why Ketoconazole Is the Target

- **Ketoconazole**: Potent CYP3A4 inhibitor → dramatically increases ibrutinib AUC → risk of severe toxicity → **Do Not Coadminister (Red)**
- **Fluconazole**: Moderate CYP3A4 inhibitor → moderate interaction (lower severity)
- **Acenocoumarol**: No significant pharmacokinetic interaction with ibrutinib → Green/no interaction

The agent must screen all three and identify ketoconazole as the most severe without being told which is worst.

## Verification Strategy

**Export pipeline**: `export_result.sh` runs `uiautomator dump`, greps the XML for drug names and screen text, writes `/sdcard/ibrutinib_contraindication_result.json`.

**Verifier scoring** (`verifier.py::verify_ibrutinib_comedication_contraindication_screen`):

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| Gate 1 (identity) | 0 or fail | Ibrutinib visible on screen |
| Gate 2 (target) | 0 or 5 | Ketoconazole visible (not wrong co-med) |
| Drug pair on screen | +20 | Both ibrutinib and ketoconazole visible |
| Severity indicator | +25 | "Do Not Coadminister" text visible |
| Interaction Details page | +35 | "Interaction Details" text visible (deepest navigation) |
| CYP3A4 mechanism text | +20 | CYP3A4 text in interaction details |
| **Pass threshold** | **≥ 70** | |

## Difficulty Justification

**Very Hard**: The agent must:
1. Discover the app's drug selection workflow independently (no UI steps given)
2. Screen three co-medications sequentially against ibrutinib
3. Compare interaction ratings across all three results
4. Identify ketoconazole as the most severe without being told
5. Navigate from the Results screen to the deeper Interaction Details view
6. Remain on the correct screen at task end

Step count: ~35–50 UI interactions (navigation to cancer drug, three co-med selections, comparison, deep navigation to details screen).

## Technical Notes

- **App package**: `com.liverpooluni.ichartoncology`
- **Result JSON**: `/sdcard/ibrutinib_contraindication_result.json`
- **XML dump**: `/sdcard/ibrutinib_contraindication_dump.xml`
- **Environment**: Android AVD 34, 1080×2400 resolution
- All scripts use `#!/system/bin/sh` (POSIX sh, not bash)
- Do-nothing baseline: app is on Welcome screen; no drug names visible → all flags false → score=0

## Evidence

Evidence files are stored in `examples/liverpool_cancer_ichart_env/evidence_docs/`:
- `ibrutinib_comedication_contraindication_screen_evidence.json`
