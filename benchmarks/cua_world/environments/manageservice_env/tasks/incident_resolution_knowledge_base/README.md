# Task: incident_resolution_knowledge_base

## Domain Context

**Occupation**: Senior IT Support Specialist / Computer User Support Specialist
**Industry**: Information Technology — Enterprise Help Desk
**Why realistic**: Senior IT support staff routinely do end-of-week ticket closure and knowledge capture. Resolving tickets involves entering specific, accurate resolution notes (not just clicking "Resolve"), then converting the fix into a reusable Knowledge Base article so other technicians can handle the same issue faster next time. This two-phase workflow — close tickets with good documentation, then publish a KB article — is a standard ITSM best practice and part of ITIL's Knowledge Management process.

---

## Goal

Two long-running tickets need to be closed out, and a Knowledge Base article needs to be created from the fix. The end state must include:

1. **Ticket 1002** (email issue — "cannot send or receive emails") resolved with resolution text that documents the SMTP relay fix, status set to **Resolved**
2. **Ticket 1005** (Adobe Acrobat — "need Adobe Acrobat Pro installed") resolved with resolution text documenting the SCCM software push, status set to **Resolved**
3. **Ticket 1002 status further updated to Closed** (not just Resolved)
4. A **Knowledge Base solution article** created in the Solutions module with the title **"Troubleshooting SMTP Email Issues After Maintenance Windows"** containing the SMTP relay fix details

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Ticket 1002 resolved | 25 | Status changed from Open (+5 bonus if resolution text contains 'smtp' or 'relay') |
| Ticket 1005 resolved | 20 | Status changed from Open (+5 bonus if resolution text contains 'acrobat' or 'sccm') |
| Ticket 1002 closed | 15 | Status further updated to Closed (distinct from Resolved) |
| KB article created | 30 | Solution article with 'SMTP' in title exists in Solutions module |

**Pass threshold**: 60/100 (score capped at 100)
**Difficulty**: very_hard

---

## Verification Strategy

The `export_result.sh` script:
1. Queries PostgreSQL `workorderstates` for `statusid` of tickets 1002 and 1005
2. Queries resolution text from `workordertoresolution` or `resolution` tables for both tickets; checks for 'smtp'/'relay' in 1002 and 'acrobat'/'adobe'/'sccm' in 1005
3. Queries for KB/solution articles: `solution` or `knowledgebase` tables; looks for title containing 'smtp'
4. Cross-checks via REST API: `GET /api/v3/requests/1002` and `/api/v3/requests/1005` for status.name and resolution fields
5. Calls `GET /api/v3/solutions` or `/api/v3/knowledge_base_articles` to check for SMTP article
6. Writes all results to `/tmp/incident_resolution_knowledge_base_result.json`

The `verifier.py` function `verify_incident_resolution_knowledge_base`:
- **Wrong-target gate**: If neither ticket changed status AND no SMTP KB article exists → score=0
- **Criterion 1**: `ticket_1002_resolved` (status != Open) + bonus `smtp_in_resolution_1002`
- **Criterion 2**: `ticket_1005_resolved` (status != Open) + bonus `acrobat_in_resolution_1005`
- **Criterion 3**: `ticket_1002_closed` (must be 'Closed', not just 'Resolved')
- **Criterion 4**: `kb_smtp_article_exists` (title contains 'smtp' case-insensitively)
- Score capped at 100 (bonus points can push above base)

---

## Schema Reference

**Key tables (PostgreSQL, port 65432, database `servicedesk`):**

```sql
-- Check ticket status
SELECT statusid FROM workorderstates WHERE workorderid IN (1002, 1005);
-- statusid: 2=Open, 3=In Progress, 4=Resolved, 5=Closed (exact values may vary)

-- Check resolution text
SELECT resolution FROM workordertoresolution WHERE workorderid = 1002;

-- Check KB articles
SELECT * FROM solution WHERE LOWER(title) LIKE '%smtp%';
-- or: SELECT * FROM knowledgebase WHERE LOWER(title) LIKE '%smtp%';
```

**REST API (https://localhost:8080/api/v3/):**
- `GET /api/v3/requests/{id}` — includes `status.name` and resolution text
- `GET /api/v3/solutions` — list Knowledge Base / Solutions articles
- `GET /api/v3/knowledge_base_articles` — alternative endpoint

---

## Pre-existing Data

The two target tickets created at task setup:
- **Ticket 1002**: "Email account issue - Cannot send or receive emails" — Software category, Medium priority, Open
- **Ticket 1005**: "Adobe Acrobat Pro - Need PDF editor installed" — Software category, Low priority, Open

Resolution texts are provided verbatim in the task description so the agent knows what to enter:
- Ticket 1002: Must reference SMTP relay settings changed during maintenance window, port 587, TLS
- Ticket 1005: Must reference Adobe Acrobat Pro DC, SCCM push deployment

---

## Edge Cases and Potential Issues

- **Resolved vs. Closed**: ServiceDesk Plus has separate "Resolved" and "Closed" statuses. The agent must first set to Resolved (which allows entering resolution text), then separately update to Closed. Some workflows require a different path for each.
- **Resolution text field**: The resolution text field is only available when setting a ticket to Resolved status. If the agent sets to Closed directly, the resolution text may not be capturable.
- **Solutions module location**: Knowledge Base articles are in the "Solutions" module (separate from Requests). The agent must navigate there to create the article, not just close a ticket.
- **Resolution text storage**: The table storing resolution text may be `workordertoresolution`, `resolution`, or embedded in the `workorder` table depending on SDP version. The export script tries multiple approaches.
- **KB article fields**: The Solutions module may require a Title, Content/Description, and Topic/Category. The agent must fill these in to successfully create the article.
- **Wrong-target risk**: The agent should resolve the correct tickets (1002 = email issue, 1005 = Adobe). Resolving other tickets will not score points since the verifier checks specific workorderids.
