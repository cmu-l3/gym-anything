# mailing_list_triage

## Task Overview

**Difficulty**: very_hard
**Occupation context**: IT Team Lead / DevOps Manager
**Timeout**: 900 seconds (80 steps)

An IT Team Lead (Operations Managers are the top BlueMail occupation by GDP) has accumulated weeks of mailing list traffic in their inbox. Multiple technical mailing lists — spanning security discussions, Linux user groups, development lists, and community forums — are all mixed together in one inbox, making it impossible to prioritise and track important threads. The inbox currently has 50 unread messages from several distinct mailing lists, with no folder organisation whatsoever.

---

## Goal (End State)

The agent must independently determine what the end state should look like. The goal is a **fully organised inbox**:

- Distinct mailing list folders exist in the email client (named after each list)
- All mailing list emails have been moved to their respective folders
- The inbox is substantially cleared (fewer than 35 emails remaining)
- A summary email has been drafted and addressed to `devops-team@techcorp.org`

The summary must report which mailing lists were identified, how many emails were in each, and any time-sensitive threads noticed. The exact folder names, the exact number of folders, and the exact phrasing of the summary are all left to the agent's judgement — there are no prescribed UI steps.

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Folders created | 25 | 2+ custom IMAP folders exist after task (partial: 10pts for 1 folder) |
| Inbox reduced | 25 | Inbox has fewer than 35 emails (15+ moved out); partial credit for 5+ moved |
| Folders populated | 15 | Custom folders collectively contain 15+ emails; partial for 5–14 |
| Summary email drafted | 25 | Draft or sent email addressed to `devops-team@techcorp.org` |
| Relevant subject | 10 | Subject contains: triage / inbox / mailing / organize / list / sorted / complete |

**Pass threshold**: 70 / 100 (requires at least partial email composition in addition to organising)

---

## Starting State

- 50 real ham emails from the SpamAssassin public corpus loaded into inbox
- Emails are from multiple mailing lists: SAdev, ILUG, zzzzteana, SAtalk, exmh-workers, IRR, etc.
- No custom folders exist — only default IMAP folders (Junk, Drafts, Sent, Trash)
- Baseline recorded in `/tmp/initial_inbox_count`

---

## Verification Strategy

1. **Maildir filesystem query** (primary): After the task, `export_result.sh` reads `/home/ga/Maildir/` to count inbox emails and enumerate custom folders (detected as `.FolderName/` directories, excluding defaults). Email counts per folder are extracted directly from the filesystem.
2. **Draft/Sent parsing**: All files in `.Drafts/cur/`, `.Drafts/new/`, `.Sent/cur/`, `.Sent/new/` are parsed for `To:`, `Subject:`, `CC:`, `BCC:` headers and first 20 body lines.
3. **VLM bonus**: Optional visual check (+5 pts) if folders appear in the BlueMail sidebar.

**Result file**: `/tmp/task_result.json`

Key fields used by verifier:
```
inbox_count                    — current inbox email count
custom_folder_count            — number of non-default IMAP folders
custom_folders                 — {folder_name: email_count} dict
total_emails_in_custom_folders — sum of all emails across custom folders
drafts / sent                  — list of {to, subject, cc, bcc, body} dicts
```

---

## Data Source

All 50 emails are real messages from the **SpamAssassin public corpus** (Apache SpamAssassin project). They originate from real mailing lists:

- `SAdev` — SpamAssassin development list
- `ILUG` — Irish Linux Users Group
- `zzzzteana` — personal/digest list
- `SAtalk` — SpamAssassin user discussions
- `exmh-workers` — exmh email client developers list
- `IRR` — Internet Routing Registry

Emails are stored as `.eml` files at `/workspace/assets/emails/ham/ham_001.eml` through `ham_050.eml`.

---

## Edge Cases and Potential Issues

- **Mailing list detection**: Agents must examine email headers (List-Id, X-Mailing-List, Reply-To, subject prefixes like [ILUG]) to identify which list an email belongs to. Some emails have no explicit list header and require subject/sender heuristics.
- **Partial folders**: An agent that creates only 1 folder still gets 10 partial points for that criterion.
- **Wrong recipient**: If the summary email is sent to a wrong address, criterion 4 scores 0. The exact address `devops-team@techcorp.org` must appear in the `To:` field.
- **IMAP sync**: BlueMail reads from Dovecot IMAP at localhost:993. Folder creation in the GUI should propagate to Maildir as `.FolderName/` directories. If BlueMail is closed before export, moved messages may not be synced — the export script runs after agent finishes.
- **Inbox count discrepancy**: `ls Maildir/cur/ | wc -l` counts all files including system flags. The export script uses Python to count only regular files.
