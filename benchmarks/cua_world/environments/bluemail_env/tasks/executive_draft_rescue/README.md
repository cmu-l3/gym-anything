# executive_draft_rescue (`executive_draft_rescue@1`)

## Overview
This task evaluates the agent's ability to review, edit, and manage work-in-progress emails. Acting as an Executive Assistant, the agent must audit a set of existing drafts, complete and send a critical business communication, and clean up irrelevant personal drafts.

## Rationale
**Why this task is valuable:**
- **Context Switching:** Tests the ability to pick up work initiated by someone else (a common collaborative workflow).
- **Draft Management:** Verifies competence in handling the Drafts folder (editing vs. discarding).
- **Editor Interaction:** Requires modifying body text (appending content) rather than just sending as-is.
- **Decision Making:** Requires distinguishing between business-critical and irrelevant content based on the scenario.

**Real-world Context:** Executives often start emails on their mobile devices or between meetings and leave them unfinished. An assistant is frequently tasked with "cleaning up the drafts folder"—sending what's ready and discarding accidental or stale stubs.

## Task Description

**Goal:** Audit the **Drafts** folder, finish and send the proposal email, and delete the stale lunch coordination draft.

**Starting State:** 
BlueMail is open. The **Drafts** folder contains 3 specific pre-loaded emails:
1.  **To:** `client.relations@strategic-partners.com` | **Subject:** "Q3 Strategic Proposal - Draft" | **Body:** "Hi Sarah, per our discussion yesterday, here is the..." (Incomplete)
2.  **To:** `lunch-club@internal.team` | **Subject:** "Taco Tuesday?" | **Body:** "Are we going to..." (Stale/Personal)
3.  **To:** `vendor-billing@suppliers.net` | **Subject:** "Invoice #9928 Query" | **Body:** "Please hold off on payment." (To be kept for later)

**Expected Actions:**
1.  Navigate to the **Drafts** folder.
2.  Open the proposal draft to `client.relations@strategic-partners.com`.
3.  Complete the sentence in the body by typing: **"initial draft of the Q3 report for your review."**
4.  **Send** the completed proposal email.
5.  Locate the personal draft with subject "Taco Tuesday?".
6.  **Delete** (discard) the "Taco Tuesday?" draft.
7.  Leave the "Invoice #9928 Query" draft untouched.

**Final State:**
- The proposal email is in the **Sent** folder with the completed sentence.
- The "Taco Tuesday?" draft is deleted (moved to Trash or gone).
- The "Invoice" draft remains in the Drafts folder.

## Verification Strategy

### Primary Verification: Maildir State Analysis
The verification script inspects the filesystem state of the local Maildir:

1.  **Sent Verification**: Checks `~/Maildir/.Sent/` for an email where:
    -   `To` contains `client.relations`
    -   Body contains the phrase "initial draft of the Q3 report" (Evidence of editing)
    -   Body contains "per our discussion yesterday" (Evidence of using the correct original draft)

2.  **Deletion Verification**: Checks `~/Maildir/.Drafts/` to ensure no email exists with specific subject words "Taco" or "Tuesday".

3.  **Preservation Verification**: Checks `~/Maildir/.Drafts/` to ensure the "Invoice" email still exists.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Proposal Sent | 30 | Email to `client.relations` found in Sent folder |
| Proposal Edited | 30 | Body text includes required completion phrase (anti-gaming) |
| Stale Draft Deleted | 20 | "Taco Tuesday" draft is no longer in Drafts |
| Invoice Draft Kept | 20 | "Invoice" draft remains in Drafts |
| **Total** | **100** | |

**Pass Threshold:** 80 points (Must send the edited email and perform at least one cleanup action).