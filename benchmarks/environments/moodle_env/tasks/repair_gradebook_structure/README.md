# Task: Repair Gradebook Structure

## Overview

**Occupation**: Course Coordinator / Academic Affairs
**Difficulty**: very_hard
**Course**: CHEM201 — Organic Chemistry I (Science category)
**Login**: admin / Admin1234!
**Application URL**: http://localhost/moodle

A newly created course CHEM201 has a completely broken gradebook configuration. All six grade items were inserted at the flat top-level with the wrong aggregation method (Mean of grades). The agent must discover this broken state by inspecting the gradebook, then restructure it to match the official course syllabus by creating three weighted categories, moving each grade item into the correct category, and configuring multi-level weights throughout.

## Initial Broken State

When the task starts, CHEM201's gradebook looks like this:

- **Top-level aggregation**: Mean of grades (code 0) — WRONG, should be Weighted mean (code 10)
- **Structure**: All 6 items dumped flat at the course level with no sub-categories
  - Problem Set 1 (manual, 100 pts)
  - Problem Set 2 (manual, 100 pts)
  - Lab Report 1 (manual, 100 pts)
  - Lab Report 2 (manual, 100 pts)
  - Midterm Exam (manual, 100 pts)
  - Final Exam (manual, 100 pts)

## Target State (Correct Syllabus Policy)

The agent must transform the gradebook into the following three-tier structure:

```
CHEM201 — Organic Chemistry I  [Weighted mean of grades, aggregation code 10]
├── Problem Sets  [weight: 30]  [Simple weighted mean]
│   ├── Problem Set 1  (equal weight within category)
│   └── Problem Set 2  (equal weight within category)
├── Lab Reports  [weight: 30]  [Simple weighted mean]
│   ├── Lab Report 1  (equal weight within category)
│   └── Lab Report 2  (equal weight within category)
└── Exams  [weight: 40]  [Weighted mean of grades]
    ├── Midterm Exam  (weight: 40 within Exams)
    └── Final Exam    (weight: 60 within Exams)
```

### Actions Required

1. Log in to Moodle as admin
2. Navigate to CHEM201 course
3. Go to Gradebook setup (Grades > Setup tab or Gradebook setup link)
4. Edit the top-level course grade category:
   - Change aggregation from "Mean of grades" to "Weighted mean of grades"
5. Add grade category "Problem Sets"
6. Add grade category "Lab Reports"
7. Add grade category "Exams"
8. Move grade items into their respective categories:
   - Problem Set 1, Problem Set 2 → Problem Sets
   - Lab Report 1, Lab Report 2 → Lab Reports
   - Midterm Exam, Final Exam → Exams
9. Set top-level category weights:
   - Problem Sets = 30
   - Lab Reports = 30
   - Exams = 40
10. Set Exams sub-weights:
    - Midterm Exam = 40 (within Exams)
    - Final Exam = 60 (within Exams)
11. Save all changes

## Verification Criteria (100 points total)

| # | Criterion | Points | Database Check |
|---|-----------|--------|---------------|
| 1 | Top-level aggregation = Weighted mean (code 10) | 20 | `mdl_grade_categories.aggregation WHERE courseid=CHEM201 AND depth=1` |
| 2 | "Problem Sets" category exists | 10 | `mdl_grade_categories WHERE fullname LIKE '%problem set%' AND depth > 1` |
| 2b | "Problem Sets" weight = 30 (±6) | 10 | `mdl_grade_items.aggregationcoef WHERE itemtype='category' AND iteminstance=problem_sets_id` |
| 3 | "Lab Reports" category exists | 10 | `mdl_grade_categories WHERE fullname LIKE '%lab report%' AND depth > 1` |
| 3b | "Lab Reports" weight = 30 (±6) | 10 | `mdl_grade_items.aggregationcoef WHERE itemtype='category' AND iteminstance=lab_reports_id` |
| 4 | "Exams" category exists | 10 | `mdl_grade_categories WHERE fullname LIKE '%exam%' AND depth > 1` |
| 4b | "Exams" weight = 40 (±6) | 10 | `mdl_grade_items.aggregationcoef WHERE itemtype='category' AND iteminstance=exams_id` |
| 5a | Midterm Exam sub-weight = 40 (±8) within Exams | 5 | `mdl_grade_items.aggregationcoef WHERE itemname LIKE '%midterm%' AND categoryid=exams_id` |
| 5b | Final Exam sub-weight = 60 (±8) within Exams | 5 | `mdl_grade_items.aggregationcoef WHERE itemname LIKE '%final%' AND categoryid=exams_id` |

**Pass threshold**: 60 points AND criterion 1 must be fully satisfied (correct top-level aggregation is mandatory).

## Why This Task is Hard

1. **Discovery required**: The agent must first inspect the gradebook to understand the broken flat structure before knowing what to fix — the task description describes the desired end state from a syllabus, not a step-by-step procedure.

2. **Multi-level weight configuration**: Moodle's gradebook UI requires navigating multiple pages and save steps to set weights at both the top-level (category weights) and within the Exams category (item sub-weights). A single save does not persist all settings.

3. **Item movement UX**: Moving grade items between categories in Moodle 4.5 involves drag-and-drop or a non-obvious dropdown menu per item in the gradebook setup table. The agent must do this for all 6 items.

4. **Aggregation method cascade**: The top-level must use Weighted mean (code 10), while subcategories may use Simple weighted mean (code 11) or Weighted mean depending on their internal structure. Setting the wrong aggregation at any level silently produces incorrect grade calculations.

5. **High step count**: Performing all required changes (1 aggregation edit + 3 category creations + 6 item moves + 3 top-level weights + 2 sub-weights) easily exceeds 20 UI actions, requiring efficient navigation under a 80-step budget.

## Verification Strategy

- **Setup baseline**: Initial state has 0 sub-categories and aggregation code 0 (Mean).
- **Category existence**: Check `mdl_grade_categories` for category names with case-insensitive LIKE matching.
- **Weight retrieval**: JOIN `mdl_grade_categories` with `mdl_grade_items` on `iteminstance=gc.id AND itemtype='category'` — the `aggregationcoef` column on that item record holds the category's weight in its parent.
- **Sub-weights**: For Exams items, query `mdl_grade_items` where `categoryid` equals the Exams category id, filtering by itemname for Midterm and Final.
- **Tolerance**: Category weights allow ±6% tolerance. Exam sub-weights allow ±8% tolerance. This accommodates both percentage values (0.30, 0.40) and point values (30, 40) that Moodle may store depending on how the UI was used.

## Database Schema Reference

- `mdl_grade_categories`: id, courseid, fullname, aggregation, depth, parent
  - aggregation: 0=Mean, 10=Weighted mean, 11=Simple weighted mean, 13=Natural
  - depth=1 is root course category; depth=2 are direct sub-categories
- `mdl_grade_items`: id, courseid, itemtype, itemname, iteminstance, categoryid, aggregationcoef, aggregationcoef2
  - itemtype='category': the row representing a grade category in the grade tree; aggregationcoef = weight
  - itemtype='manual': a manually-graded item; categoryid = its parent category
  - aggregationcoef: weight of this item within its parent aggregation

## Edge Cases

- Moodle may store category weights as decimals (0.30) or integers (30) depending on UI interaction mode. The verifier handles both by applying generous tolerances.
- The top-level course grade category always exists at depth=1; sub-categories created by the agent appear at depth=2.
- If the agent creates categories with slightly different names (e.g., "Problem Set" vs "Problem Sets"), LIKE matching with wildcards should still find them.
- The Exams sub-weights (Midterm 40, Final 60) sum to 100; the verifier checks each independently within tolerance.
