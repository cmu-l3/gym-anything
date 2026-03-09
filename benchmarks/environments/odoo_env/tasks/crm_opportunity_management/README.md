# Task: CRM Opportunity Management

## Difficulty: Very Hard

## Occupation Context
**Primary occupations**: Customer Service Representatives ($2.91B GDP), Sales Representatives – Wholesale/Manufacturing ($832M GDP)
**Why realistic**: CRM pipeline hygiene is a core responsibility of sales teams. Identifying stale deals, archiving lost opportunities, advancing active deals to correct stages, and scheduling follow-up activities are all real daily CRM operations. This task requires navigating the CRM module across all its major features simultaneously.

## Scenario
The sales pipeline for **Horizon Technologies Ltd** (a key account) has not been maintained. Two opportunities exist:
1. **"Legacy System Migration & Modernization"** — created 45 days ago, stuck in "New" stage, no activity (STALE)
2. **"Enterprise Cloud License Renewal"** — recently active, in "Qualified" stage (ACTIVE)

The agent must:
1. Identify which opportunity is stale (>30 days old, early stage) and mark it as **Lost** with reason "No Response / Stale Opportunity"
2. For the active opportunity: advance to **Proposition** stage, set expected revenue to **$65,000**, schedule a **Phone Call** activity titled "Follow-up call - Horizon Technologies" due in **7 days**
3. Add an **internal note** to the active opportunity confirming cleanup actions

## Why This Is Very Hard
- Agent must evaluate both opportunities and make a judgment call about which is stale
- No explicit instructions on which menu to use or how to mark an opportunity as lost
- Three sequential independent actions required: archive stale, update active, add note
- Activity scheduling in Odoo requires knowing the Activities workflow (chatter)
- Wrong target (updating stale instead of active) would fail revenue/stage criteria

## Setup Details
`setup_task.sh` performs:
1. Creates company "Horizon Technologies Ltd" (if not exists)
2. Creates two CRM opportunities for this company
3. Updates the stale opportunity's `create_date` and `write_date` to 45 days ago via SQL
4. Saves setup metadata to `/tmp/crm_opportunity_setup.json`

## Verification Criteria (100 points)
| Criterion | Points | Check |
|-----------|--------|-------|
| Stale opportunity archived/marked lost with reason | 25 | `active=False` + `lost_reason_id` |
| Active opportunity advanced to Proposition stage | 20 | `stage.name` contains 'Proposition' |
| Expected revenue set to $65,000 | 15 | `expected_revenue == 65000` |
| Phone call activity scheduled (~7 days out) | 20 | `mail.activity` with phone type + deadline |
| Internal note added (mentions cleanup) | 20 | `mail.message` with 'cleanup'/'stale' text |
| **Pass threshold** | **65** | **Must score ≥65** |

## Key Odoo Tables
- `crm.lead` — opportunities and leads (active/inactive, stage_id, expected_revenue)
- `crm.stage` — pipeline stages
- `crm.lead.lost.reason` — lost reasons
- `mail.activity` — scheduled activities per record
- `mail.message` — chatter messages (notes)

## Features Exercised
- CRM module: Pipeline Kanban view, List view, Opportunity form
- CRM stages: drag-and-drop or form-field stage change
- Activity scheduling: Add Activity button in chatter
- Chatter: Log Note feature for internal notes
- Mark as Lost workflow: Lost button → reason selection
