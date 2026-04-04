# Task: account_consolidation

## Overview

A CRM deduplication and account consolidation task. The agent must identify which
of two nearly-identical company records is the designated primary, migrate all
contacts and opportunities to that primary record, archive the duplicate, and
clean up associated tags — simulating a real data governance process.

## Domain Context

Duplicate company records are a common CRM problem. They arise from manual data
entry errors, system migrations, or multiple salespeople creating records
independently. Consolidating them requires identifying the canonical record,
reassigning all related data, documenting the action, and decommissioning the
duplicate. This task replicates a real sales operations consolidation workflow.

## Goal

Consolidate two duplicate "Meridian" company records:

1. **Identify the primary record**: The primary is indicated by an internal note
   on "Meridian Solutions Grp" (note the intentional abbreviation "Grp" vs "Group").
2. **Move contacts**: Three contacts (Amanda Cortez, Ben Holloway, Celia Park) are
   currently attached to the non-primary company and must be moved to the primary.
3. **Reassign opportunities**: All three Meridian opportunities must be linked to
   the primary company record.
4. **Archive the duplicate**: "Meridian Solutions Group" (the non-primary) must be
   archived (active=False).
5. **Post a consolidation note**: A new internal note must be added to the primary
   record documenting the merge action (written by the agent, distinct from the
   pre-existing notice note).
6. **Remove dedup tag**: The 'Requires-Deduplication' partner category tag must be
   removed from the primary company record.
7. **Tag consolidated opportunities**: All 3 opportunities must receive the
   'Account-Deduped' tag.

## Starting State

| Entity                    | Linked To                  | Notes                          |
|---------------------------|----------------------------|--------------------------------|
| Meridian Solutions Group  | (Company A — non-primary)  | Has 'Requires-Deduplication' tag |
| Meridian Solutions Grp    | (Company B — PRIMARY)      | Has PRIMARY NOTICE note + dedup tag |
| Amanda Cortez (VP Sales)  | Meridian Solutions Group   | Must move to B                 |
| Ben Holloway (CTO)        | Meridian Solutions Group   | Must move to B                 |
| Celia Park (Finance Dir.) | Meridian Solutions Group   | Must move to B                 |
| David Osei (CEO)          | Meridian Solutions Grp     | Already on primary             |
| Eva Lindqvist (COO)       | Meridian Solutions Grp     | Already on primary             |
| Meridian ERP Phase 1 ($65k)  | Meridian Solutions Group | Must reassign to B             |
| Meridian Security Audit ($28k)| Meridian Solutions Group| Must reassign to B             |
| Meridian Annual License ($42k)| Meridian Solutions Grp | Already on primary             |

## Verification Strategy

Export reads the parent_id of each contact (checking if it equals Company B's ID),
the partner_id of each opportunity, active status of Company A, presence of new
messages on Company B posted after task_start_timestamp, category_id list on
Company B (checking for removal of 'Requires-Deduplication'), and tag_ids on
each opportunity (checking for 'Account-Deduped').

The agent must read the chatter/note on Company B to discover which record is
primary — this cannot be inferred from the company name alone without looking
at the note.

## Key Database Tables

- `res_partner` — contacts and companies (parent_id, is_company, active, category_id)
- `res_partner_category` — partner tags/categories (name)
- `res_partner_res_partner_category_rel` — many2many linking partners to categories
- `crm_lead` — opportunities (partner_id, tag_ids)
- `crm_tag` — opportunity tags
- `mail_message` — chatter messages (res_model, res_id, body, date)

## Scoring Breakdown

| Criterion                                                | Points |
|----------------------------------------------------------|--------|
| Amanda Cortez parent = primary company                   | 5      |
| Ben Holloway parent = primary company                    | 5      |
| Celia Park parent = primary company                      | 5      |
| Meridian ERP Phase 1 partner = primary company           | 6      |
| Meridian Security Audit partner = primary company        | 6      |
| Meridian Annual License partner = primary company        | 6      |
| Company A (non-primary) archived                         | 15     |
| Company B has new internal note after task start         | 17     |
| 'Requires-Deduplication' tag removed from primary        | 10     |
| All 3 opps tagged 'Account-Deduped' (8 pts each)        | 25     |
| **Total**                                                | **100**|

**Pass threshold: 60 points**
