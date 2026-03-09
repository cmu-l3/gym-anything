# Task: add_study_site

**Difficulty**: Hard
**Environment**: openclinica_env@0.1
**Task ID**: add_study_site@1

---

## Task Description

This task exercises the multi-site expansion workflow in OpenClinica. The agent must act
as a Clinical Data Manager (CDM) responsible for onboarding a new academic medical center
into a running cardiovascular registry. This requires navigating the Build Study wizard to
create a site record, and then enrolling subjects at two different levels — the parent
study and the site — demonstrating an understanding of OpenClinica's hierarchical study
structure.

---

## Professional Context

In multi-site clinical research, a "site" (also called an "investigational site" or
"clinical site") is a physical location where the study is conducted. OpenClinica models
this by storing site records in the `study` table with a `parent_study_id` foreign key
pointing to the parent study. When subjects are enrolled at a site, their `study_subject`
row has `study_id` equal to the site's `study_id`, not the parent's. This distinction is
critical for regulatory compliance, data segregation, and site-level reporting.

The Cardiovascular Outcomes Registry (CV-REG-2023) scenario is realistic: a Phase III
outcomes registry expanding to a large academic heart center mid-trial. The CDM must:

1. Add the site record through the GUI (Build Study → Study Site → Add Study Site).
2. Enroll a subject into the parent study directly (for global registry-level enrollment).
3. Navigate to the site context and enroll a second subject specifically at that site.

---

## Ground Truth Values

| Item | Expected Value |
|------|---------------|
| Study Identifier | CV-REG-2023 |
| Site Name | Boston Heart Institute |
| Site Protocol ID (unique_identifier) | CV-BHI-001 |
| Site Principal Investigator | Dr. Sarah Chen |
| Subject CV-101 | Male, DOB 1952-03-18, enrolled at parent study |
| Subject CV-102 | Female, DOB 1967-11-05, enrolled at Boston Heart Institute site |

---

## Setup Behavior (setup_task.sh)

The setup script:
- Locates the CV-REG-2023 study by `unique_identifier` in the `study` table.
- Deletes any pre-existing sites (study rows with matching `parent_study_id`) and their
  associated subjects, ensuring a clean baseline.
- Deletes any pre-existing CV-prefixed subjects at the parent study level.
- Records baseline site and subject counts in `/tmp/initial_site_count` and
  `/tmp/initial_cv_subject_count`.
- Starts Firefox, logs in as root, and switches the active study to CV-REG-2023.
- Records an audit baseline count and generates an integrity nonce.

---

## Verification Strategy (verifier.py)

The verifier uses a multi-criterion scoring model:

### Criterion 1 — Site Found in Database (30 pts)
Queries the `study` table for any row with `parent_study_id` = CV Registry's `study_id`
and `status_id != 3` (not removed). Checks that the site name contains "Boston" and
"Heart". A newly added site is confirmed by comparing current vs. initial site counts.

### Criterion 2 — Correct Site Protocol ID (10 pts)
Checks that the site's `unique_identifier` matches "CV-BHI-001" (case-insensitive).
The PI field ("Dr. Sarah Chen") is checked informally and reported in feedback.

### Criterion 3 — CV-101 Enrolled at Parent Study (25 pts)
Looks for a `study_subject` row with `label = 'CV-101'` and `study_id` = CV Registry's
`study_id`. Awards full 25 pts for correct gender (Male) and exact DOB (1952-03-18),
with tiered partial credit (18/14/10 pts) for partially correct demographics.

### Criterion 4 — CV-102 Enrolled (25 pts + 5 bonus)
First checks for CV-102 at the site level (`study_id` = site's `study_id`), then falls
back to checking at the parent level. Awards full 25 pts for correct gender (Female) and
DOB (1967-11-05), with tiered partial credit. Awards an additional +5 bonus pts if
CV-102 was correctly enrolled at the site level rather than the parent.

### VLM Visual Check (up to 10 pts)
Analyzes the final screenshot with a VLM to confirm OpenClinica is in a successful,
non-error state and that relevant identifiers (site name, subject IDs) are visible.
Awards 5 pts for a visible success/details page and 5 pts for site/subject identifiers
being present on-screen.

### Audit Log Penalty (-20 pts)
If no new audit log entries are found since setup, 20 points are deducted to penalize
direct SQL bypass rather than legitimate GUI interaction.

### Pass Threshold
Score >= 70 AND site_found = True AND at least one subject found AND audit log confirms
GUI interaction.

---

## Key OpenClinica Navigation Steps

1. **Switch active study**: Home → "Change Study/Site" or top-right study dropdown →
   select "Cardiovascular Outcomes Registry".
2. **Add site**: Build Study (left sidebar or top menu) → Study Site → Add Study Site →
   fill in Name, Unique Protocol ID, Principal Investigator → Submit.
3. **Enroll CV-101 at parent**: Ensure active context is the parent study (not the site)
   → Subject Matrix → Add Subject → fill in CV-101 details → Save.
4. **Enroll CV-102 at site**: Switch active context to "Boston Heart Institute" site →
   Subject Matrix → Add Subject → fill in CV-102 details → Save.

---

## DB Schema Reference

```sql
-- Site record
SELECT study_id, name, unique_identifier, principal_investigator, parent_study_id
FROM study
WHERE parent_study_id = <cv_registry_study_id>;

-- Subjects at parent
SELECT ss.label, sb.gender, sb.date_of_birth
FROM study_subject ss
JOIN subject sb ON ss.subject_id = sb.subject_id
WHERE ss.study_id = <cv_registry_study_id>;

-- Subjects at site
SELECT ss.label, sb.gender, sb.date_of_birth
FROM study_subject ss
JOIN subject sb ON ss.subject_id = sb.subject_id
WHERE ss.study_id = <site_study_id>;
```
