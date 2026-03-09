# Birthday Party RSVP Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Conditional formulas (IF, SUMIF, COUNTIF), data updates, conditional formatting  
**Duration**: 180 seconds (3 minutes)  
**Steps**: ~15

## Objective

Manage a messy real-world birthday party guest list by updating RSVPs from multiple sources, creating summary formulas to calculate accurate headcounts, and applying conditional formatting for visual priority management. This simulates the chaotic reality of event planning where data arrives asynchronously from emails, texts, and verbal conversations.

## Context

You're organizing your child's birthday party at a venue that needs the final headcount in 5 days. Your spreadsheet has partial RSVP data. This morning you received two updates:
- **Jake's mom texted**: "We're coming! 2 adults + Jake"
- **Sarah's parents emailed**: "Sorry, can't make it"

You need to update the tracker, calculate totals, and visually identify outstanding responses.

## Starting State

LibreOffice Calc opens with a pre-populated guest list containing:
- **Columns**: Guest Name | Child Name | RSVP Status | # Adults | # Kids | Dietary Notes | Contact
- **Data**: 7 families with mixed "Yes", "No", and "Pending" responses
- **Jake's row** (Row 3): Status = "Pending" (needs update)
- **Sarah's row** (Row 4): Status = "Pending" (needs update)
- **Summary section** (Rows 11-15): Empty cells needing formulas

## Required Actions

### 1. Update RSVP Data
- Find **Jake** (Johnson Family, Row 3) and update:
  - RSVP Status → "Yes"
  - # Adults → 2
  - # Kids → 1
- Find **Sarah** (Davis Family, Row 4) and update:
  - RSVP Status → "No"

### 2. Create Summary Formulas
Navigate to Summary section (around Row 12+) and enter:
- **Total Adults Attending**: `=SUMIF(C:C,"Yes",D:D)` (sums # Adults where Status = "Yes")
- **Total Kids Attending**: `=SUMIF(C:C,"Yes",E:E)` (sums # Kids where Status = "Yes")
- **Total Guests**: Sum of adults + kids
- **Pending Responses**: `=COUNTIF(C:C,"Pending")` (counts remaining "Pending")

### 3. Apply Conditional Formatting (Optional but Recommended)
- Select RSVP Status column (C)
- Format → Conditional Formatting → Condition
- Create rules:
  - "Pending" → Yellow background
  - "Yes" → Light green background
  - "No" → Light gray background

### 4. Highlight Dietary Restrictions (Optional)
- Select Dietary Notes column (F)
- Apply conditional formatting: If cell not empty → Orange background

## Expected Results After Updates

Based on the sample data, after updating Jake and Sarah:
- **Total Adults**: Should be 9 (Smith 2 + Jake's family 2 + Williams 2 + Brown 1 + Martinez 2)
- **Total Kids**: Should be 6 (Emma 1 + Jake 1 + Liam 2 + Olivia 1 + Ava 1)
- **Total Guests**: 15
- **Pending**: 1 or 2 remaining families

## Success Criteria

1. ✅ **Data Updated**: Jake's row shows "Yes", 2 adults, 1 kid; Sarah's row shows "No"
2. ✅ **Formulas Present**: Summary section contains SUMIF/COUNTIF formulas (minimum 3)
3. ✅ **Calculations Correct**: Formula results match expected totals (±1 tolerance)
4. ✅ **Conditional Formatting Applied**: RSVP Status column has color-based rules (minimum 2 rules)
5. ✅ **Dietary Highlighting**: Non-empty dietary notes are visually flagged

**Pass Threshold**: 75% (requires at least 4 out of 5 criteria, or 3 core criteria if formatting missing)

## Skills Tested

- Data scanning and completeness assessment
- Cell editing and data updates
- Conditional formula creation (IF, SUMIF, COUNTIF)
- Counting and summing with criteria
- Conditional formatting application
- Real-world data management under time pressure

## Tips

- Use Ctrl+F to quickly find "Jake" and "Sarah" in the spreadsheet
- SUMIF syntax: `=SUMIF(range_to_check, criteria, sum_range)`
- COUNTIF syntax: `=COUNTIF(range_to_check, criteria)`
- Conditional formatting: Select column → Format menu → Conditional Formatting
- The summary section has labeled rows to guide formula placement