# School Read-a-thon Fundraiser Tracker Task (`school_readathon_tracker@1`)

## Overview

This task tests an agent's ability to manage a realistic fundraising campaign with messy data, multiple pledge types, and conditional calculations. The agent must organize sponsor commitments, create formulas that handle different pledge structures, calculate summary statistics, and optionally generate collection letters for unpaid sponsors.

## Task Description

**Goal**: Clean up and analyze a chaotic read-a-thon fundraiser spreadsheet with two pledge types (per-book and flat), calculate amounts owed, generate summary statistics, and optionally create collection letters.

**Starting State**: 
- Spreadsheet: `/home/ga/Documents/Spreadsheets/ReadAthon_Data.xlsx`
- Contains 28 rows of messy pledge data with:
  - Student names
  - Sponsor names (individuals and businesses)
  - Pledge types: "Per Book" or "Flat"
  - Pledge amounts with inconsistent formatting ("$2", "2", "$2.00")
  - Books read (some blank for non-participating students)
  - Payment status ("Paid", "Pending", or blank)
  - Contact information

**Expected Actions**:

1. **Add "Amount Owed" column** (Column H):
   - Create formulas that calculate based on pledge type:
     - "Per Book": Pledge Amount × Books Read
     - "Flat": Just the Pledge Amount
   - Handle blank/zero books read (should = $0)

2. **Create summary section** (around row 35):
   - Total Amount Pledged (sum of all amounts owed)
   - Total Amount Collected (sum where status = "Paid")
   - Total Amount Outstanding (pledged minus collected)

3. **OPTIONAL - Create collection letters**:
   - Document: `/home/ga/Documents/TextDocuments/Collection_Letters.docx`
   - Include sponsor names, amounts owed, professional tone

## Real-World Context

**Scenario**: You're a parent volunteer who inherited a chaotic read-a-thon spreadsheet compiled from paper pledge forms. Some sponsors have paid, many haven't. The principal needs a status update tomorrow showing:
- How much money is coming in total
- How much has been collected
- How much is still outstanding
- Who needs collection letters

The data is messy because it came from handwritten forms collected by multiple teachers.

## Verification Criteria (7 total, need 5+ to pass)

1. ✅ **Spreadsheet file exists and is parseable**
2. ✅ **"Amount Owed" column present** with data in Column H (or nearby)
3. ✅ **Per-book formulas correct** (spot-check 3+ rows: amount = pledge × books)
4. ✅ **Flat pledge formulas correct** (spot-check 3+ rows: amount = pledge)
5. ✅ **Summary statistics present** (Total Pledged, Collected, Outstanding)
6. ✅ **Summary statistics mathematically accurate** (within 5% tolerance)
7. ✅ **Collection letter document exists** with appropriate content (BONUS)

## Scoring System

- **100%**: All 7 criteria met (perfect execution with bonus)
- **85-99%**: 6/7 criteria met (excellent work)
- **70-84%**: 5/7 criteria met (core task complete, passing)
- **50-69%**: 4/7 criteria met (partial completion)
- **0-49%**: <4 criteria met (insufficient progress)

**Pass Threshold**: 70% (requires accurate formulas + summary statistics)

## Skills Tested

- **Conditional formula logic** (IF statements for pledge types)
- **Data cleaning** (handling inconsistent currency formats)
- **Null handling** (blank cells in "Books Read")
- **Aggregate functions** (SUM, SUMIF for totals)
- **Real-world problem solving** (understanding fundraising business logic)
- **Multi-application workflow** (spreadsheet + optional document)
- **Professional communication** (collection letter tone)

## Expected Execution Time

- **Novice agent**: 12-18 minutes
- **Experienced agent**: 6-10 minutes  
- **Human expert**: 8-12 minutes (experienced volunteer coordinator)

## Example Formula Solution
