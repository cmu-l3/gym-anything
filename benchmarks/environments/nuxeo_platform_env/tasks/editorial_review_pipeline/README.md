# editorial_review_pipeline

**Difficulty:** very_hard
**Occupation:** Digital Content Manager
**Industry:** Media / Publishing

## Overview

A digital content manager performs the Q4 publication cycle review in the Nuxeo content management system. This involves reading the editorial standards, assessing four articles for metadata completeness, updating missing metadata, applying workflow tags, creating editorial assessment notes, and building the Q4 2025 Publications collection.

## Setup State

The `setup_task.sh` script creates four articles with varying states of metadata completeness:

| Document | dc:source | dc:rights | dc:language | Expected Tag |
|----------|-----------|-----------|-------------|--------------|
| Feature Article: Climate Change | ❌ empty | ❌ empty | ❌ empty | needs-revision (→ update all) |
| Research Report: AI Ethics | ✅ set | ❌ empty | ❌ empty | needs-revision (→ update rights, language) |
| Opinion Column: Economic Policy | ✅ set | ✅ set | ✅ set | ready-for-review (already complete) |
| Breaking News: Tech Sector | ❌ empty | ❌ empty | ❌ empty | needs-revision (→ update all) |

Also creates `Editorial Standards and Publication Guidelines` Note in Projects workspace (the reference doc).

## Agent Goal

1. Read the `Editorial Standards and Publication Guidelines` document
2. Review each document against the 3 required metadata fields: dc:source, dc:rights, dc:language
3. Update missing fields to appropriate values (any non-empty value satisfies the requirement)
4. Apply `ready-for-review` tag to documents with all 3 fields populated
5. Apply `needs-revision` tag to documents still missing one or more fields
6. Create an editorial assessment Note (titled "[Document Title] — Editorial Assessment") for each reviewed document
7. Create collection `Q4 2025 Publications` and add all `ready-for-review` documents to it

## Verification Criteria

| Criterion | Points |
|-----------|--------|
| dc:source set on ≥2 of the 3 initially-empty docs | 12 pts |
| dc:rights set on ≥2 of the 3 initially-empty docs | 12 pts |
| dc:language set on ≥2 of the 3 initially-empty docs | 11 pts |
| Opinion-Column correctly tagged 'ready-for-review' | 8 pts |
| ≥2 incomplete docs tagged 'needs-revision' | 10 pts |
| ≥1 doc fully updated AND tagged 'ready-for-review' | 7 pts |
| Editorial assessment Notes created (≥3 docs) | 20 pts |
| Collection 'Q4 2025 Publications' created | 5 pts |
| Collection has ≥1 ready-for-review article | 15 pts |
| **Total** | **100 pts** |

**Pass threshold:** 60/100

## Features Tested

- Metadata editing (dc:source, dc:rights, dc:language)
- Tagging (`@tagging` endpoint)
- Note creation
- Collections
- Document review workflows (discovery-driven)

## Notes

- The agent must read the editorial standards to understand which fields are required and what tags to apply.
- The Opinion Column already satisfies all requirements — agent should recognize it as `ready-for-review` without modification.
- Assessment notes are discovered in the verifier by searching for Notes with "Assessment" in the title within the Projects workspace.
- The collection should contain documents tagged `ready-for-review`. If the agent updates all 4 articles, all 4 should be in the collection.
