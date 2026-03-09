# spam_infiltration_response

## Task Overview

**Difficulty**: hard
**Occupation context**: IT Security Manager / Operations Manager
**Timeout**: 720 seconds (60 steps)

An IT Security Manager has discovered that the organisation's spam filter was briefly misconfigured, allowing 10 spam messages to bypass the filter and land in the main inbox mixed among legitimate email. The spam filter has since been corrected, but the 10 infiltrated spam messages still sit in the inbox. The security team must now: quarantine the spam, create an incident tracking folder, and draft an incident report for the security response team.

This task tests the IT Security Manager's workflow for responding to a spam filter bypass event — a realistic scenario for Operations Managers and Security staff who are the top BlueMail occupational user groups.

---

## Goal (End State)

- The 10 spam emails that bypassed the filter have been identified and moved to the Junk folder
- A folder named **`Spam-Incidents`** has been created in the email client
- At least 2 of the identified spam emails have been moved/copied to `Spam-Incidents` as evidence
- A draft or sent email has been addressed to `security-response@company.com` documenting the incident

The report to `security-response@company.com` should reference the spam bypass event, include a count of affected messages, and use appropriate security/incident terminology.

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Spam quarantined | 25 | Junk folder count increased by 7+ from baseline of 10; partial for 3–6 increase |
| Spam-Incidents folder created | 20 | A folder named `Spam-Incidents` exists (case-insensitive match) |
| Spam-Incidents populated | 15 | Folder contains 2+ emails; partial for exactly 1 |
| Incident report drafted | 25 | Draft or sent email to `security-response@company.com` |
| Report quality | 15 | Report body/subject includes spam terminology AND a numeric count; partial for terms only |

**Pass threshold**: 65 / 100

---

## Starting State

- **Inbox**: 40 real ham emails + 10 real spam emails (spam bypassed filter scenario)
  - Ham: `ham_001.eml` through `ham_040.eml`
  - Spam planted in inbox: `spam_001.eml` through `spam_010.eml`
- **Junk folder**: 10 pre-existing spam emails (`spam_011.eml` through `spam_020.eml`)
  - Baseline Junk count = 10, recorded in `/tmp/initial_junk_count`
- No custom folders exist initially

The agent knows spam has infiltrated the inbox (stated in the task description) but must independently identify which emails are spam.

---

## Verification Strategy

1. **Junk count delta** (primary): Export script counts emails in `.Junk/cur/` and `.Junk/new/` and computes increase from baseline (`/tmp/initial_junk_count` = 10). An increase of 7+ means most spam was quarantined.
2. **Custom folder detection**: Maildir scan for `.Spam-Incidents/` (case-insensitive). If the folder exists and has 2+ messages, criterion 3 passes.
3. **Draft/Sent parsing**: All draft and sent files are parsed for `To:`, `Subject:`, body content.
4. **Report quality scoring**: Combined subject + body is scanned for spam-related terms (`spam`, `incident`, `bypass`, `filter`, `junk`, `phishing`, `unsolicited`) AND for at least one digit (`\b\d+\b`).
5. **VLM bonus**: Optional visual confirmation (+5 pts) if `Spam-Incidents` folder visible in sidebar.

**Result file**: `/tmp/task_result.json`

Key fields:
```
junk_count / junk_increase     — current Junk count and delta from baseline
spam_incidents_folder_exists   — boolean
spam_incidents_count           — email count in Spam-Incidents folder
custom_folders                 — {folder_name: count} for all non-default folders
drafts / sent                  — list of {to, subject, cc, bcc, body}
```

---

## Data Source

All emails are real messages from the **SpamAssassin public corpus**:

- **Ham**: `ham_001.eml`–`ham_040.eml` — real messages from technical mailing lists (SAdev, ILUG, etc.)
- **Spam (in inbox)**: `spam_001.eml`–`spam_010.eml` — real spam messages from the SpamAssassin corpus
- **Spam (in Junk)**: `spam_011.eml`–`spam_020.eml` — same corpus, pre-loaded as baseline

All spam files are at `/workspace/assets/emails/spam/spam_XXX.eml`.

---

## Edge Cases and Potential Issues

- **Spam identification**: The agent must use heuristics (suspicious senders, subject lines like "MAKE MONEY FAST", generic greetings) to distinguish the 10 spam emails from 40 legitimate ham emails. No explicit labelling is given.
- **Junk threshold**: Criterion 1 requires 7+ spam moved to Junk (not all 10). This allows for cases where 1-3 spam messages are ambiguous or might be missed.
- **Spam-Incidents naming**: The verifier uses case-insensitive matching, so `spam-incidents`, `Spam_Incidents`, etc. will not match — only `Spam-Incidents` or exact case variants of that specific name. The task description specifies the exact folder name.
- **Wrong report recipient**: The exact address `security-response@company.com` must appear in `To:` of the draft/sent email.
- **Report body parsing**: Only the first 30 lines of email body are read by the export script (to avoid reading large attachments or HTML). Agents should write concise reports.
