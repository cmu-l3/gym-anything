# domain_analysis_and_reporting

## Task Overview

**Difficulty**: hard
**Occupation context**: Operations Manager / Administrative Assistant
**Timeout**: 720 seconds (65 steps)

An Operations Manager is performing a routine email correspondence audit required by the compliance team. The audit requires identifying which external domains send the most email to the organisation, creating organised folders for the top sender domains, sorting correspondence into domain-specific folders, and drafting an audit report for the compliance team.

This task reflects the real Administrative Assistant and Operations Manager workflow (top BlueMail occupations) of maintaining email governance, tracking external correspondence patterns, and reporting to compliance. The specific domains must be discovered from the actual email corpus — they are not told in advance.

---

## Goal (End State)

The agent must independently analyse the inbox to identify the top 3 sender domains. A correctly completed task looks like:

- **3 or more folders** prefixed with `Domain-` created (e.g., `Domain-linux.ie`, `Domain-sf-bugs.openbsd.org`)
- At least 2 of the 3 actual top sender domains (by email count) are covered by the created folders
- Emails from each domain sorted into the corresponding `Domain-` folder
- A draft or sent email addressed to `audit-compliance@yourcompany.com` containing an audit report

The audit report subject should reference audit/domain/report/compliance, and the body should mention at least 2 domain names (in the format `word.word` or `word.word.word`).

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Domain- folders created | 20 | 3+ folders with `Domain-` prefix exist |
| Top domains covered | 25 | At least 2 of the dynamically-computed top-3 sender domains are covered by created folders |
| Audit email drafted | 25 | Draft or sent to `audit-compliance@yourcompany.com` |
| Relevant subject | 15 | Subject of audit email contains: audit / domain / report / compliance / analysis / sender |
| Domain names in body | 15 | Body of audit email mentions 2+ domain-like strings (pattern: `\w+\.\w+`) |

**Pass threshold**: 65 / 100

---

## Starting State

- **Inbox**: All 50 real ham emails from SpamAssassin corpus (`ham_001.eml`–`ham_050.eml`)
- No custom folders exist
- **Dynamic ground truth**: During setup, `setup_task.sh` scans all inbox emails' `From:` headers, extracts sender domains, and saves the top-3 to `/tmp/top_sender_domains.json`

The agent does not receive the top sender domains in the task description — they must examine inbox emails to discover which domains are most represented.

---

## Dynamic Domain Discovery

Because the SpamAssassin corpus has real, fixed sender distributions, the top 3 domains are deterministic but not hardcoded in task.json. Instead, setup_task.sh computes them at setup time:

```json
{
  "top_domains": ["sf-bugs.openbsd.org", "linux.ie", "rzlab.ucr.edu"],
  "domain_counts": {
    "sf-bugs.openbsd.org": 14,
    "linux.ie": 9,
    "rzlab.ucr.edu": 7,
    ...
  }
}
```

The verifier loads this file from the VM and checks whether the agent's `Domain-` folder names contain strings matching the top-3 domain names. This ensures the verifier always reflects the actual corpus, not a hardcoded assumption.

---

## Verification Strategy

1. **Folder detection**: Maildir scan for folders starting with `.Domain-`. Names are recorded.
2. **Top domain matching**: Load `/tmp/top_sender_domains.json` from VM. For each top domain, check if any created `Domain-` folder name contains that domain as a substring. Count how many of the top-3 are covered. Requires 2+ for full credit.
3. **Audit email**: Parse all drafts and last 5 sent emails. Check `To:` for `audit-compliance@yourcompany.com`.
4. **Subject check**: Scan subject for: `audit`, `domain`, `report`, `compliance`, `analysis`, `sender`.
5. **Body domain check**: Scan body for strings matching regex `\w+\.\w+` (domain-like patterns). Requires 2+ distinct matches.

**Result file**: `/tmp/task_result.json`

Key fields:
```
inbox_count                  — current inbox count
domain_folders               — {folder_name: email_count} for Domain- prefixed folders
domain_folder_count          — number of Domain- folders
top_domains_covered          — list of top-3 domains found in folder names
top_domains_covered_count    — int: how many top-3 domains are covered
drafts / sent                — list of {to, subject, cc, bcc, body}
```

---

## Data Source

All 50 emails are real messages from the **SpamAssassin public corpus** (`ham_001.eml`–`ham_050.eml`). The sender domains reflect real technical mailing list infrastructure (OpenBSD bug tracker, Irish Linux Users Group, UCR research lab, etc.). These are genuine external correspondence domains, making the compliance audit scenario authentic.

Email assets at: `/workspace/assets/emails/ham/ham_001.eml`–`ham_050.eml`

---

## Edge Cases and Potential Issues

- **Domain discovery challenge**: The agent must examine email `From:` headers to identify sender domains. Some emails have display names like `"John Smith" <john@linux.ie>` — the domain is in the angle-bracket address, not the display name.
- **Folder name matching**: The verifier checks if any `Domain-` folder name *contains* a top domain name as a substring. So `Domain-linux.ie` matches domain `linux.ie`, and `Domain-sf-bugs` would *not* match `sf-bugs.openbsd.org` (not a substring). Agents should use the full domain.
- **2-of-3 tolerance**: The task requires only 2 of the top-3 domains to be covered (not all 3), allowing for cases where one domain is ambiguous or has few emails.
- **Audit email address**: `audit-compliance@yourcompany.com` must appear verbatim (case-insensitive) in the `To:` field.
- **Body domain regex**: The check uses `\w+\.\w+` which matches any dot-separated word pair. Domain names, hostnames, and even email addresses all qualify. Agents need at least 2 such strings in the body — easily satisfied by mentioning 2 domain names in the report.
