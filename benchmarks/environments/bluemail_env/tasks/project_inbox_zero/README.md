# project_inbox_zero

## Task Overview

**Difficulty**: very_hard
**Occupation context**: Software Project Manager / IT Operations Manager
**Timeout**: 900 seconds (80 steps)

A Software Project Manager has a partially organised inbox. A colleague previously created two folders (`Security-Discussion` and `Hardware-Issues`) and moved 5 emails into each, but then got pulled away. There are still 40 emails sitting unsorted in the inbox. The project manager must complete the organisation: create additional thematic folders, finish sorting all remaining emails, achieve inbox zero (≤ 5 emails remaining), and report the final folder structure to the project director.

This task is **very_hard** because: the agent must independently decide what additional folders to create, what themes exist in the remaining 40 emails, and how to present the outcome — no prescribed folder names, no prescribed structure, no navigation instructions.

---

## Goal (End State)

The agent must determine the end state independently. A correctly completed task looks like:

- **3 or more NEW folders** created (beyond the pre-existing `Security-Discussion` and `Hardware-Issues`)
- **Inbox cleared**: 5 or fewer emails remain in the inbox
- All new folders are populated (2+ emails each)
- A **status email** has been drafted or sent to `project-director@devteam.com` listing the complete folder structure

The exact folder names, the folder themes, the email distribution across folders, and the status report wording are all left to the agent's discretion.

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| 3+ new folders | 25 | 3 or more folders created BEYOND Security-Discussion and Hardware-Issues; partial 10pts for 1–2 new |
| Inbox zero | 25 | Inbox has ≤ 5 emails; partial 12pts for 6–15 remaining |
| New folders populated | 15 | All new folders have 2+ emails each (≥80% threshold); partial for at least 1 populated |
| Status email sent | 25 | Draft or sent to `project-director@devteam.com` |
| Folder names in body | 10 | Status email body/subject mentions 3+ folder names; partial 4pts for 1–2 |

**Pass threshold**: 65 / 100

---

## Starting State

**Pre-existing folders (created by setup):**

| Folder | Emails | Content |
|--------|--------|---------|
| `Security-Discussion` | 5 | `ham_011.eml`–`ham_015.eml` (SAdev security threads) |
| `Hardware-Issues` | 5 | `ham_016.eml`–`ham_020.eml` (ILUG hardware discussions) |

**Inbox (40 emails):**
- `ham_001.eml`–`ham_010.eml` + `ham_021.eml`–`ham_050.eml`
- Mix of SAdev (security), ILUG (Linux/hardware), zzzzteana (general), SAtalk (spam filter), exmh-workers (app dev), IRR (routing), and other mailing list content

**Baseline files:**
- `/tmp/initial_inbox_count` = 40
- `/tmp/initial_custom_folder_count` = 2

---

## Verification Strategy

The export script (`export_result.sh`) uses Python to:
1. Enumerate all Maildir folders, classifying them as:
   - `pre_existing_folders`: Security-Discussion, Hardware-Issues
   - `new_folders`: all other non-default folders
2. Count emails in each folder
3. Determine `new_folders_with_2plus_emails` (populated count)
4. Parse all drafts and last 5 sent emails for headers and body

The verifier then:
1. Checks `new_folder_count` (not total — only folders beyond the 2 pre-existing)
2. Checks `inbox_count <= 5`
3. Checks `new_folders_populated / new_folder_count >= 0.8`
4. Checks `drafts + sent` for `project-director@devteam.com` in To field
5. Checks body of status email for mentions of folder names from `all_custom_folders`

**Result file**: `/tmp/task_result.json`

Key fields:
```
inbox_count                    — current inbox email count
all_custom_folder_count        — total custom folders (including pre-existing)
new_folder_count               — folders created by agent (excludes pre-existing)
new_folders                    — {name: count} for agent-created folders only
all_custom_folders             — {name: count} for ALL custom folders
new_folders_with_2plus_emails  — count of new folders with 2+ emails
drafts / sent                  — list of {to, subject, cc, bcc, body}
```

---

## Data Source

All emails are real messages from the **SpamAssassin public corpus**:
- `ham_001.eml`–`ham_050.eml` at `/workspace/assets/emails/ham/`

The pre-existing folder contents (`ham_011`–`ham_020`) were selected to represent realistic folder themes (security threads for `Security-Discussion`, hardware/Linux discussions for `Hardware-Issues`), making the partially-organised state feel authentic.

---

## Edge Cases and Potential Issues

- **Folder naming freedom**: The agent may name new folders anything. The verifier only checks count (3+) and population (2+ emails each), not specific names. The body check looks for any folder names mentioned.
- **Pre-existing folder boundary**: The verifier explicitly subtracts the 2 pre-existing folders from the total. Creating 5 total folders = 3 new = passes criterion 1.
- **Inbox zero strictness**: "Inbox zero" allows up to 5 emails remaining (some may be system messages or emails the agent intentionally leaves). The threshold is 5, not 0.
- **Status email body length**: Only the first 20 lines of email body are captured by the export script. Agents should mention folder names near the top of their status report.
- **IMAP sync timing**: If the agent creates folders and moves emails but BlueMail hasn't synced to Dovecot before export, counts may be off. The setup script restarts Dovecot before loading emails, and the export runs after agent completion.
