# Legal Case Triage and Routing

## Task Overview

**Difficulty**: Very Hard
**Domain**: Legal / Law Firm Administration
**Professional Context**: Real paralegals at law firms spend significant time managing case correspondence in email clients. Whitmore & Associates uses Thunderbird for all case communication. A backlog of mixed emails has accumulated and must be organized before partner review.

## Background

The inbox contains 12 emails spanning three active legal matters:

1. **Harrison v. Mercer** (employment discrimination) — 5 emails from client David Harrison, opposing counsel, and the court clerk
2. **DataVault Systems IP Dispute** (patent infringement) — 4 emails from client DataVault CTO, Hartley Patent Group (opposing counsel), and USPTO
3. **Chen Family Estate** (estate administration) — 3 emails from family members and the probate court

Additionally, there are general office emails mixed in.

## What Constitutes Success

The agent must determine the correct case for each email by reading sender addresses and subject lines, then:

1. **Create a nested folder structure**: Local Folders > Cases > Harrison_Mercer, DataVault_IP, Chen_Estate
2. **Route emails**: Move each email to its correct case subfolder by reading content
3. **Add opposing counsel to address book**: Marcus Webb (mwebb@hartleypatent.com) from Hartley Patent Group
4. **Create a message filter**: Future emails from courtclerk@district.court → Court_Notices folder
5. **Create Court_Notices folder** (required by the filter)

## Verification Strategy

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| Cases parent folder created | 10 | Check Cases.sbd directory in Local Folders |
| Harrison_Mercer subfolder with ≥4 emails | 20 | Check mbox file + count "From " lines |
| DataVault_IP subfolder with ≥3 emails | 20 | Check mbox file + count "From " lines |
| Chen_Estate subfolder with ≥2 emails | 15 | Check mbox file + count "From " lines |
| Marcus Webb contact in address book | 20 | Query abook.sqlite for email match |
| Court filter or Court_Notices folder | 15 | Check msgFilterRules.dat or folder existence |

**Pass threshold**: 60 points
**Wrong-target guard**: Score = 0 if wrong emails placed in folders (checked by email count sanity)

## Schema Reference

- Mbox folders: `~/.thunderbird/default-release/Mail/Local Folders/`
- Nested subfolders: `~/.thunderbird/default-release/Mail/Local Folders/Cases.sbd/`
- Filter rules: `~/.thunderbird/default-release/Mail/Local Folders/msgFilterRules.dat`
- Address book: `~/.thunderbird/default-release/abook.sqlite`

## Edge Cases

- Agent may name folders slightly differently (Harrison-Mercer, Harrison_v_Mercer) — verifier accepts common variants
- Agent may add filter before creating folder, or vice versa — both orderings are fine
- Thunderbird may not flush filter file until closed — export script closes Thunderbird first
