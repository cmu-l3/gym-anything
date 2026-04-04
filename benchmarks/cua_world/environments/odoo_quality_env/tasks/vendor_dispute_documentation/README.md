# vendor_dispute_documentation

## Domain Context

**Occupation**: Regulatory Affairs Manager
**Industry**: Office Components Manufacturing
**Software**: Odoo 17 Quality Module (Quality Alerts + Quality Control Points)
**Difficulty**: very_hard

Regulatory Affairs Managers must formally close supplier non-conformance records before regulatory submission deadlines, following specific closure procedures: document corrective and preventive actions, escalate priority to reflect regulatory significance, assign vendor accountability, and formally close the record. They must also update quality control protocols to prevent recurrence.

## Task Description

A regulatory submission deadline in 48 hours requires formal closure of a supplier batch non-conformance. The agent must find the quality alert titled **"Surface Coating Defect on Cabinet Batch 2025-Q1"** and:

1. **Add corrective action** documenting immediate containment measures for the defective batch
2. **Add preventive action** documenting the supplier process change to prevent recurrence
3. **Set priority to Urgent** to reflect regulatory significance
4. **Assign a partner/vendor** from the system as the responsible party
5. **Transition to Done** stage to formally close the corrective action record

Additionally, to prevent future coating defects from going undetected:
6. **Create a new Pass/Fail QCP** for "Acoustic Bloc Screens" with a failure message describing what to do when coating inspection fails

## Starting State

`setup_task.sh` creates the target alert fresh each run:
- Alert name: "Surface Coating Defect on Cabinet Batch 2025-Q1"
- Stage: New
- Priority: Normal (0)
- corrective_action: '' (empty)
- preventive_action: '' (empty)
- partner_id: False (no vendor assigned)

Also removes any prior pass/fail coating QCPs for Acoustic Bloc Screens.

## Verification Strategy

**Multi-criterion scoring (100 pts total, pass ≥ 60):**

| Criterion | Points | Condition |
|-----------|--------|-----------|
| C1: Corrective action | 18 pts | corrective_action ≥ 10 chars |
| C2: Preventive action | 18 pts | preventive_action ≥ 10 chars |
| C3: Priority Urgent | 14 pts | priority = '2' or '3' |
| C4: Partner assigned | 15 pts | partner_id is set |
| C5: Done stage | 15 pts | stage = Done |
| C6: New Pass/Fail QCP with failure_message | 20 pts | passfail QCP for Acoustic Screens + failure_message ≥ 10 |
| C6 partial (passfail, no message) | 10 pts | QCP found, no failure_message |
| C6 partial (wrong type) | 5 pts | QCP found but wrong test type |

**Note on C4**: If no partners exist in the system, C4 is automatically awarded (15 pts). The system comes with demo partners (res.partner records) so this should not be an issue.

**Scoring paths to pass (≥60)**:
- Complete all 5 alert changes (18+18+14+15+15=80) → PASS even without QCP
- All 5 alert changes + partial QCP (80+10=90) → PASS
- Miss one alert change + full QCP (e.g., 62+20=82 from 4 changes) → PASS
- Miss partner + stage (18+18+14=50) → FAIL, must also create QCP

## Schema Reference

- **Model**: `quality.alert`
  - `name`: "Surface Coating Defect on Cabinet Batch 2025-Q1"
  - `corrective_action`: Html field
  - `preventive_action`: Html field
  - `priority`: '0'=Normal, '1'=High, '2'=Urgent, '3'=Blocker
  - `partner_id`: Many2one → res.partner
  - `stage_id`: Many2one → quality.alert.stage (target: Done)
- **Model**: `quality.point`
  - `test_type`: 'passfail'
  - `product_ids`: Many2many including "Acoustic Bloc Screens"
  - `failure_message`: Html/text

## Files

- `task.json` — task configuration and hooks
- `setup_task.sh` — creates fresh target alert, removes stale QCPs
- `export_result.sh` — reads all 5 alert fields, finds new passfail QCP
- `verifier.py` — 6-criterion scoring

## Edge Cases

- Agent may not find the right alert if they search imprecisely: export looks up by exact name
- Pass/Fail QCP may not be linked to Acoustic Screens product: export falls back to searching by name keywords ("Acoustic", "Coating")
- HTML formatting in corrective/preventive actions: stripped before length check
