# compliance_metadata_remediation

**Difficulty:** very_hard
**Occupation:** Compliance Analyst
**Industry:** Financial Services

## Overview

A regulatory compliance analyst must audit documents in the Nuxeo ECM system against the firm's metadata compliance standards (SEC Rule 17a-4, SOX Section 802, FINRA Rule 4511) and remediate all non-compliant records.

## Setup State

The `setup_task.sh` script:
1. Seeds three non-compliant documents:
   - `Project Proposal` — description is a placeholder ("placeholder text - needs update"), no coverage, no subjects
   - `Annual Report 2023` — missing dc:coverage and dc:subjects
   - `Contract Template` — dc:expired date is in the past (2024-06-30), lifecycle still in "project" state
2. Creates a `Document Metadata Compliance Standards` Note in the Projects workspace (the reference doc the agent must read)
3. Opens Firefox on the Nuxeo home page

## Agent Goal

1. Read the `Document Metadata Compliance Standards` note to learn requirements
2. Audit all documents against the 4 standards: description length, coverage, subjects, and expired lifecycle
3. Remediate each non-compliant document by updating its metadata
4. Apply the `compliance-reviewed` tag to each remediated document
5. Add a comment to each remediated document describing what was corrected
6. Transition the Contract Template to `obsolete` lifecycle state
7. Create collection `Q4 2025 Compliance Audit` and add all remediated documents to it

## Verification Criteria

| Criterion | Points |
|-----------|--------|
| `compliance-reviewed` tag on each of 3 in-scope docs | 10 pts each = 30 pts |
| Comment on each of 3 in-scope docs | 5 pts each = 15 pts |
| Project-Proposal description updated (≥50 chars, non-placeholder) | 10 pts |
| Annual-Report-2023 dc:coverage populated | 5 pts |
| Annual-Report-2023 dc:subjects populated | 5 pts |
| Contract-Template lifecycle = 'obsolete' | 15 pts |
| Collection 'Q4 2025 Compliance Audit' created | 5 pts |
| Collection contains all 3 remediated docs | 15 pts |
| **Total** | **100 pts** |

**Pass threshold:** 60/100

## Features Tested

- Metadata editing (dc:description, dc:coverage, dc:subjects)
- Tagging (`@tagging` endpoint)
- Comments (`@comment` endpoint)
- Collections
- Lifecycle transitions (`@op/Document.FollowLifecycleTransition`)

## Notes

- The compliance standards document is the agent's only source of truth for requirements.
- The agent must read it and infer which documents are non-compliant; the task description does not list them by name.
- Q3-Status-Report may exist from other tasks but is not non-compliant per the seeded state.
