# Task: venetoclax_cyp3a4_induction_risk_assessment

## Domain Context

**Occupation**: Clinical Pharmacologist
**Industry**: Pharmaceutical Drug Safety / Haematology Oncology
**Environment**: Liverpool Cancer iChart Archive (Android app, `com.liverpooluni.ichartoncology`)

Clinical pharmacologists in pharmaceutical drug safety teams are responsible for systematically characterising the drug-drug interaction profile of newly approved oncology drugs. Venetoclax is a BCL-2 inhibitor approved for CLL and AML with a complex pharmacokinetic profile: it is a substrate of CYP3A4 and P-glycoprotein. Among the important interaction classes to document in a drug safety dossier are (1) CYP3A4 inhibitors (which increase venetoclax exposure → toxicity) and (2) CYP3A4/CYP2C8 inducers (which decrease venetoclax exposure → sub-therapeutic levels and risk of treatment failure or resistance). Carbamazepine is a prototypic strong CYP3A4 inducer used as the inducer class representative in drug safety assessments.

## Goal

You are conducting a systematic interaction risk assessment for a venetoclax drug safety dossier. Three co-medications representing different interaction classes are being evaluated:

- **Warfarin** — anticoagulant (CYP2C9 substrate, possible bidirectional interaction)
- **Fluconazole** — moderate CYP3A4 inhibitor class representative
- **Carbamazepine** — potent CYP3A4/CYP2C8 inducer class representative

Using the Liverpool Cancer iChart Archive app, look up the interaction rating for each co-medication against venetoclax. One represents an enzyme-induction mechanism that poses a critical risk of sub-therapeutic venetoclax exposure. Navigate to and remain on the **Interaction Details** screen for the co-medication representing this induction mechanism of concern.

## Success Criteria

The task is considered complete when:
1. The agent is on the **Interaction Details** screen for **Venetoclax + Carbamazepine**
2. The severity indicator is visible (expected: red/Do Not Coadminister)
3. Text describing CYP induction, reduced exposure, or AUC reduction is visible

## Why Carbamazepine Is the Target

The task description explicitly identifies the concern as the **enzyme-induction mechanism** (not enzyme-inhibition). The three co-medications represent:
- **Warfarin**: Not a CYP3A4 modulator — potential PD interaction only
- **Fluconazole**: CYP3A4 **inhibitor** (increases venetoclax levels — the opposite problem)
- **Carbamazepine**: Strong CYP3A4 **inducer** → reduces venetoclax AUC by ~65% → risk of treatment failure → **Do Not Coadminister**

The agent must identify carbamazepine as the enzyme-induction mechanism of concern based on the task description's clinical framing, not just interaction severity.

## Verification Strategy

**Export pipeline**: `export_result.sh` runs `uiautomator dump`, greps the XML for drug names, severity text, and mechanism keywords (cyp3a4, induc, exposure, auc), writes `/sdcard/venetoclax_induction_result.json`.

**Verifier scoring** (`verifier.py::verify_venetoclax_cyp3a4_induction_risk_assessment`):

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| Gate 1 (identity) | 0 or fail | Venetoclax visible on screen |
| Gate 2 (target) | 0 or 5 | Carbamazepine visible (not wrong co-med) |
| Drug pair on screen | +20 | Both venetoclax and carbamazepine visible |
| Severity indicator | +20 | "Do Not Coadminister" text visible |
| Interaction Details page | +35 | "Interaction Details" text visible |
| Induction mechanism text | +25 | CYP3A4/induc/AUC/exposure text visible |
| **Pass threshold** | **≥ 70** | |

## Difficulty Justification

**Very Hard**: The agent must:
1. Navigate the app's interaction workflow without UI guidance
2. Screen three co-medications against venetoclax
3. Apply pharmacological reasoning: identify "enzyme-induction mechanism" as carbamazepine (not fluconazole which inhibits)
4. Navigate to the Interaction Details page for the correct drug pair
5. Remain on the correct screen at task end

The task requires domain-level reasoning (distinguishing enzyme induction from enzyme inhibition as mechanisms) not just UI navigation.

## Technical Notes

- **App package**: `com.liverpooluni.ichartoncology`
- **Result JSON**: `/sdcard/venetoclax_induction_result.json`
- **XML dump**: `/sdcard/venetoclax_induction_dump.xml`
- **Environment**: Android AVD 34, 1080×2400 resolution
- All scripts use `#!/system/bin/sh` (POSIX sh, not bash)
- Do-nothing baseline: app is on Welcome screen → all flags false → score=0

## Evidence

Evidence files are stored in `examples/liverpool_cancer_ichart_env/evidence_docs/`:
- `venetoclax_cyp3a4_induction_risk_assessment_evidence.json`
