# vendor_patch_escalation

## Task Overview

**Difficulty**: hard
**Occupation context**: Operations Manager / IT Vendor Manager
**Timeout**: 720 seconds (65 steps)

An Operations Manager at a technology firm is responsible for tracking vendor software patches and escalating unresolved issues. Their inbox contains 25 recent emails including several discussions about software patches, updates, and unresolved vendor issues. The manager must identify the patch-related emails, organise them into a dedicated escalation folder, and compose a formal escalation to the vendor management and compliance teams.

This task reflects the real workflow of Operations Managers (the #1 BlueMail occupation by GDP at $915M), who regularly coordinate vendor patch timelines, manage escalations, and loop in compliance stakeholders.

---

## Goal (End State)

- A folder named **`Vendor-Escalations`** exists in the email client
- At least 3 patch/update-related emails have been moved into `Vendor-Escalations`
- A formal escalation email has been composed (draft or sent) with:
  - **CC**: `vendor-manager@acmecorp.com`
  - **BCC**: `compliance@acmecorp.com`
  - Body referencing timeline, deployment, risk, assessment, or POC contact information

The exact `To:` recipient of the escalation, the exact emails moved, and the exact wording are left to the agent's judgement. The task description names the CC and BCC addresses explicitly.

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Vendor-Escalations folder created | 20 | Folder named `Vendor-Escalations` exists |
| Folder populated | 25 | Folder contains 3+ emails; partial for 1–2 |
| CC to vendor-manager@acmecorp.com | 25 | Draft/sent email has `vendor-manager@acmecorp.com` in CC field |
| BCC to compliance@acmecorp.com | 20 | Draft/sent email has `compliance@acmecorp.com` in BCC or To field |
| Escalation content quality | 10 | Body contains: timeline / deployment / risk / assessment / contact / poc |

**Pass threshold**: 65 / 100

---

## Starting State

- **Inbox**: 25 real ham emails from SpamAssassin corpus (`ham_001.eml`–`ham_025.eml`)
  - These include emails from SAdev (security/patch discussions), ILUG (Linux/software updates), exmh-workers (application patches), and other technical lists
  - Several emails discuss patch releases, software updates, and version management — realistic for a vendor management context
- No custom folders exist
- Baseline inbox count = 25, recorded in `/tmp/initial_inbox_count`

---

## Verification Strategy

1. **Folder existence**: Maildir scan for `.Vendor-Escalations/` directory.
2. **Folder population**: Count emails in `.Vendor-Escalations/cur/` and `/new/`. Requires 3+ for full credit.
3. **CC field parsing**: Parse CC header of all draft/sent emails. Full credit if `vendor-manager@acmecorp.com` appears anywhere in the CC value.
4. **BCC field parsing**: Parse BCC header. Full credit if `compliance@acmecorp.com` appears in BCC or To (BCC may be absorbed into To depending on email client behaviour).
5. **Body content quality**: Body of the escalation email (first 30 lines) is checked for at least one of: `timeline`, `deployment`, `risk`, `assessment`, `contact`, `poc`.

**Result file**: `/tmp/task_result.json`

Key fields:
```
inbox_count                    — current inbox count
custom_folder_count            — number of non-default folders
custom_folders                 — {folder_name: count} dict
total_emails_in_custom_folders — total across all custom folders
drafts / sent                  — list of {to, subject, cc, bcc, body}
```

---

## Data Source

All 25 emails are real messages from the **SpamAssassin public corpus** (`ham_001.eml`–`ham_025.eml`). These include real technical discussions about software versions, patches, and system administration — authentic inputs for a vendor patch escalation scenario.

Email assets at: `/workspace/assets/emails/ham/ham_001.eml`–`ham_025.eml`

---

## Edge Cases and Potential Issues

- **Patch email identification**: The agent must read email subjects and content to identify which messages are patch/update related. SAdev emails often mention spam filter updates; ILUG emails discuss Linux package updates. No labelling is provided — discovery is required.
- **CC vs BCC rendering**: Some email clients convert BCC to To when composing. The verifier checks both BCC and To fields for `compliance@acmecorp.com` to handle this.
- **Exact address matching**: `vendor-manager@acmecorp.com` and `compliance@acmecorp.com` must appear verbatim (case-insensitive) in the respective fields.
- **Minimum folder population**: The task requires only 3+ emails in `Vendor-Escalations`, not necessarily all patch emails. Agents may be selective about which emails they escalate.
- **Partial credit for folder without email**: If the agent creates the folder and moves emails (45 pts) but doesn't compose the escalation (0 pts), the task fails (< 65 threshold). Both organisation AND communication are required.
