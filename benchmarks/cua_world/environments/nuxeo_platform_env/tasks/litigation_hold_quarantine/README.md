# litigation_hold_quarantine

**Difficulty:** very_hard
**Occupation:** Legal Paralegal
**Industry:** Law / Legal Services

## Overview

A legal paralegal receives a litigation hold notice for the case "Meridian Corp v. Acme Industries" (Case No. 2025-CV-04891) and must implement the preservation requirements in the Nuxeo document management system — correctly identifying in-scope documents without over-applying the hold.

## Setup State

The `setup_task.sh` script:
1. Creates two in-scope Phoenix documents:
   - `Phoenix Initiative Proposal` — references Project Phoenix, in scope
   - `Phoenix Budget Analysis Q2` — references Phoenix Initiative, in scope
2. Creates one out-of-scope decoy:
   - `Marketing Campaign Summary Q3` — no Phoenix reference, must NOT be held
3. Creates user `outside-counsel` (Robert Harrington) with Read access on all Projects documents
4. Creates `Litigation Hold Notice` Note in Projects workspace (reference document agent must read)
5. Opens Firefox on the Nuxeo home page

## Agent Goal

1. Read the `Litigation Hold Notice` to identify which documents are in scope
2. Apply `legal-hold` tag to Phoenix-Initiative-Proposal and Phoenix-Budget-Analysis
3. Add hold comment to each in-scope doc: "Document placed under litigation hold per Case No. 2025-CV-04891. Do not modify, delete, or relocate."
4. Remove all access for user `outside-counsel` from in-scope documents
5. Create collection `Litigation Hold - Meridian v Acme` and add both in-scope docs to it
6. Do NOT apply any hold actions to Marketing-Campaign-Summary

## Verification Criteria

| Criterion | Points |
|-----------|--------|
| `legal-hold` tag on Phoenix-Initiative-Proposal | 15 pts |
| `legal-hold` tag on Phoenix-Budget-Analysis | 15 pts |
| Hold comment on Phoenix-Initiative-Proposal | 10 pts |
| Hold comment on Phoenix-Budget-Analysis | 10 pts |
| Case number 2025-CV-04891 in hold comment | 5 pts |
| outside-counsel access removed from in-scope docs | 15 pts |
| Collection 'Litigation Hold - Meridian v Acme' with both docs | 20 pts |
| Marketing-Campaign-Summary NOT tagged 'legal-hold' (adversarial) | 10 pts |
| **Total** | **100 pts** |

**Pass threshold:** 60/100

## Features Tested

- Tagging (`@tagging` endpoint)
- Comments (`@comment` endpoint)
- Collections
- Permissions / ACL removal (`@op/Document.RemoveACL`, `@op/Document.BlockPermissionInheritance`)
- Document search / NXQL (agent must identify in-scope docs by reading the notice)

## Notes

- The adversarial test (10 pts) deducts from score if the agent incorrectly holds the out-of-scope decoy document.
- The agent must read the Litigation Hold Notice to know which documents are in scope — the task description intentionally does not name them.
- outside-counsel access may be managed at the document level or at the Projects workspace level.
