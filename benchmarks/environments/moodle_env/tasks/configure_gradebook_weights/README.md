# Task: Configure Gradebook Weights

## Overview
Configure a weighted gradebook for the BIO101 course by changing the aggregation method and creating grade categories with specific weights. This is essential course setup that every instructor must do — grading policies need to be configured before any assessments are given.

## Target
- Course: Introduction to Biology (BIO101)
- Login: admin / Admin1234!
- Application URL: http://localhost/moodle

## Task Description
1. Log in to Moodle as admin
2. Navigate to BIO101 course
3. Go to Gradebook setup (Grades > Setup tab)
4. Edit course grade category → Aggregation: "Weighted mean of grades"
5. Add grade category "Lab Reports"
6. Add grade category "Exams"
7. Set weights: Lab Reports = 40, Exams = 60
8. Save all changes

## Success Criteria (100 points)
| Criterion | Points | Check |
|-----------|--------|-------|
| Aggregation = Weighted mean (10) | 20 | mdl_grade_categories.aggregation WHERE depth=1 |
| Lab Reports category exists | 20 | mdl_grade_categories WHERE fullname LIKE '%Lab Reports%' |
| Exams category exists | 20 | mdl_grade_categories WHERE fullname LIKE '%Exams%' |
| Lab Reports weight ≈ 40 | 20 | mdl_grade_items.aggregationcoef WHERE itemtype='category' |
| Exams weight ≈ 60 | 20 | mdl_grade_items.aggregationcoef WHERE itemtype='category' |

Pass threshold: 60 points (must have weighted mean + both categories)

## Verification Strategy
- **Baseline**: Record initial sub-category count and initial aggregation method
- **Aggregation check**: Root category (depth=1) aggregation field
- **Weight check**: JOIN mdl_grade_categories with mdl_grade_items (itemtype='category', iteminstance=category_id)
- **Partial credit**: Simple weighted mean (11) gets 10 points; non-zero weights get 5 points

## Database Schema
- `mdl_grade_categories`: id, courseid, fullname, aggregation, depth
  - aggregation: 0=Mean, 10=Weighted mean, 11=Simple weighted mean, 13=Natural
  - depth=1 is root course category; depth>1 are sub-categories
- `mdl_grade_items`: id, courseid, itemtype, iteminstance, aggregationcoef
  - itemtype='category', iteminstance=grade_category_id → weight in aggregationcoef

## Edge Cases
- Default Moodle 4.5 aggregation is Natural (13), not Mean (0)
- Weight values stored as floats (e.g., 40.00000)
- Weight tolerance: ±5 (35-45 accepted for "40", 55-65 accepted for "60")
