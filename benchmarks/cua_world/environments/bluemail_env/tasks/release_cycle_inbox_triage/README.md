# release_cycle_inbox_triage (`release_cycle_inbox_triage@1`)

## Overview

The agent acts as a Release Manager during a "code freeze" period. The goal is to separate high-priority developer discussions from general user community chatter, identify critical release-related threads, and report the status to the project council.

## Rationale
**Why this task is valuable:**
- **Context-Aware Categorization:** Requires distinguishing between "Developer" (Signal) and "User" (Noise) sources, not just sorting by sender.
- **Keyword-Based Prioritization:** Tests the ability to scan content (subjects/bodies) for specific "trigger words" (e.g., release, patch, bug) and apply a binary state (Flag/Star).
- **Workflow Simulation:** Mimics the real-world "triage" phase of software management where sorting and highlighting are prerequisites to action.
- **Reporting:** Requires synthesizing the result of the manual work (count of flagged items) into a communication.

**Real-world Context:** During a software release cycle, a manager cannot read every email. They must isolate the developer mailing lists (where code changes happen) from user support lists, and then specifically flag threads that discuss the release or bugs for immediate review.

## Task Description

**Goal:** Segregate developer traffic from user traffic into two distinct folders, flag release-critical emails within the developer stream, and email a summary report.

**Starting State:**
- BlueMail is open with ~50 real emails in the Inbox.
- Emails are mixed from various mailing lists:
    - **Developer Lists**: `SAdev` (SpamAssassin Dev), `exmh-workers`.
    - **User/General Lists**: `SAtalk` (SpamAssassin Talk), `ILUG`, `zzzzteana`, `IRR`.
- No custom folders exist.

**Expected Actions:**
1.  **Folder Creation**: Create two new IMAP folders named exactly:
    - `Dev-High-Priority`
    - `User-Community`
2.  **Categorization**:
    - Move all emails from **Developer Lists** (look for `[SAdev]` or `exmh` in subject/headers) to `Dev-High-Priority`.
    - Move all emails from **User/General Lists** (look for `[SAtalk]`, `[ILUG]`, `zzzzteana`, etc.) to `User-Community`.
3.  **Prioritization**:
    - Open the `Dev-High-Priority` folder.
    - **Flag (Star)** any email that mentions **"release"**, **"patch"**, **"bug"**, or **"version"** in the Subject or Body.
4.  **Reporting**:
    - Compose a new email to `council@apache.org`.
    - Subject: "Release Triage Status".
    - Body: State how many emails were flagged as critical in the Dev folder. (e.g., "I have flagged 5 critical emails for the upcoming release.").

**Final State:**
- Inbox is largely empty (most emails sorted).
- `Dev-High-Priority` contains only dev-related emails, with relevant ones Flagged.
- `User-Community` contains user/general emails, none Flagged.
- A sent/draft email exists with the correct count.

## Verification Strategy

### Primary Verification: Maildir State Analysis
The verification script inspects the filesystem at `/home/ga/Maildir/`:
1.  **Folder Classification Accuracy**:
    - Scans `.Dev-High-Priority` and checks that emails originate from `SAdev` or `exmh-workers` (via `List-Id` or `Subject`).
    - Scans `.User-Community` and checks that emails originate from `SAtalk`, `ILUG`, `zzzzteana`, etc.
    - *Pass Condition*: >80% accuracy in sorting.
2.  **Flagging Logic**:
    - Counts files in `.Dev-High-Priority/cur` containing the `F` flag (filename suffix `...:2,.*F.*`).
    - Verifies that flagged emails actually contain keywords (`release`, `patch`, `bug`, `version`).
    - *Pass Condition*: At least 3 emails are flagged.
3.  **Report Consistency**:
    - Parses the email to `council@apache.org`.
    - Extracts the number mentioned in the body.
    - *Pass Condition*: The reported number matches the actual number of flagged files (±1 tolerance).

### Secondary Verification: Inbox Cleanup
- Checks that the main Inbox has fewer than 10 emails remaining (indicating a thorough sort).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Folders Created | 10 | `Dev-High-Priority` and `User-Community` exist |
| Dev Sorting Accuracy | 25 | Dev folder contains correct list emails (max 2 errors) |
| User Sorting Accuracy | 15 | User folder contains correct list emails (max 2 errors) |
| Priority Flagging | 20 | At least 3 relevant emails in Dev folder are Flagged |
| Report Drafted | 15 | Email to `council@apache.org` with correct Subject |
| Report Accuracy | 15 | Body count matches actual flagged count (±1) |
| **Total** | **100** | |

**Pass Threshold**: 70 points