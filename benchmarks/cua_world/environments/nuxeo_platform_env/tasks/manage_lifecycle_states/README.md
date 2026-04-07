# Manage Document Lifecycle States (`manage_lifecycle_states@1`)

## Overview

This task evaluates the agent's ability to manage document lifecycle states in Nuxeo Platform ECM — specifically approving reviewed documents and marking outdated documents as obsolete. It tests understanding of ECM lifecycle governance, a core capability that distinguishes enterprise content management from simple file storage.

## Rationale

**Why this task is valuable:**
- Tests a fundamental ECM operation distinct from CRUD operations on documents
- Requires understanding of document lifecycle concepts (draft → approved → obsolete)
- Validates multi-step workflow across multiple documents with different target states
- Directly tests a feature that differentiates Nuxeo from basic file sharing tools
- Real compliance implications — incorrect lifecycle states can cause audit failures

**Real-world Context:** A Document Management Specialist at a financial services firm is conducting a quarterly compliance review of the shared document repository. Company policy requires that reviewed deliverables be formally marked as "Approved" in the ECM system, and outdated documents be transitioned to "Obsolete" so they no longer surface in active searches. The firm's external auditors verify that lifecycle states accurately reflect document currency.

## Task Description

**Goal:** Update the lifecycle states of three documents in the Nuxeo Platform Projects workspace as part of a quarterly compliance review: approve two current documents and mark one outdated document as obsolete.

**Starting State:** Firefox is open and logged into Nuxeo Web UI as Administrator. The Projects workspace (`/default-domain/workspaces/Projects`) contains three documents, all currently in the **"project"** (draft) lifecycle state:
- "Annual Report 2023" (File)
- "Project Proposal" (File)
- "Q3 Status Report" (Note)

Additionally, the Templates workspace contains "Contract Template" which should **not** be modified.

**Expected Actions:**
1. Navigate to the Projects workspace in Nuxeo Web UI
2. Open the "Annual Report 2023" document and change its lifecycle state from "project" to **"approved"** (use the document's lifecycle action, typically found in the workflow/process toolbar)
3. Open the "Project Proposal" document and change its lifecycle state from "project" to **"approved"**
4. Open the "Q3 Status Report" document and change its lifecycle state from "project" to **"obsolete"**
5. Do **not** modify the "Contract Template" document in the Templates workspace — it should remain in "project" state

**Final State:** The three documents should be in these lifecycle states:
| Document | Expected State |
|----------|---------------|
| Annual Report 2023 | approved |
| Project Proposal | approved |
| Q3 Status Report | obsolete |
| Contract Template (unchanged) | project |

## Verification Strategy

### Primary Verification: REST API State Check
The verifier queries each document's `state` field via the Nuxeo REST API to confirm they match expectations.

### Secondary Verification: Anti-Gaming
- Verifies that the task started with documents in "project" state.
- Checks audit logs to ensure transitions happened *during* the task window.
- Verifies the "Contract Template" was left untouched (precision check).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Annual Report 2023 → approved | 25 | Document state is "approved" |
| Project Proposal → approved | 25 | Document state is "approved" |
| Q3 Status Report → obsolete | 25 | Document state is "obsolete" |
| Contract Template unchanged | 10 | Document state remains "project" |
| Transition evidence in audit | 5 | Audit log shows transitions after task start |
| VLM workflow evidence | 10 | Screenshots show document navigation and state changes |
| **Total** | **100** | |

**Pass Threshold:** 60 points (at least 2 of 3 lifecycle transitions correct + Contract Template unchanged)