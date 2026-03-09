# Task: open_data_government_spending_research

## Overview

**Environment**: firefox_env
**Difficulty**: Very Hard
**Occupation**: Writers and Authors / Investigative Data Journalist
**Domain**: Government Transparency, Open Data Research, Investigative Journalism

Investigative data journalists use government open data portals like USASpending.gov to research federal spending, expose waste, and contextualize policy stories. This task mirrors real workflows used by data journalists at major news organizations — searching the federal contracts database, downloading data, and synthesizing findings into research notes.

## Goal

Research Department of Defense federal contract spending on USASpending.gov and produce a research notes document.

**Multi-part task**:
1. **Search and download**: Use USASpending.gov Advanced Search to find DOD contracts (FY2023), download CSV to ~/Downloads/
2. **Agency profile**: Find DOD agency spending profile — total contracts, grants, top contractors for FY2023
3. **Cross-reference**: Visit at least one additional federal data source (fpds.gov, data.gov, or similar)
4. **Research notes**: Create `~/Documents/dod_spending_research.txt` with findings
5. **Bookmarks**: Create "Government Spending Research" Firefox folder with ≥3 USASpending.gov bookmarks

## Success Criteria

1. USASpending.gov visited multiple times (not just landing page)
2. CSV file downloaded to ~/Downloads/ with spending data (≥1KB)
3. Research notes file `~/Documents/dod_spending_research.txt` created during task (fresh)
4. Notes file contains spending figure (dollar amount with B/billion/trillion)
5. Notes file contains contractor company names
6. Notes file contains at least 2 URLs as data sources
7. Notes file has substantial content (≥200 characters)
8. "Government Spending Research" bookmark folder exists with ≥3 sec.gov/usaspending.gov bookmarks

## Verification Strategy

- **History check**: Count distinct USASpending.gov pages visited after task start
- **CSV download**: Check ~/Downloads/ for CSV files >1KB modified after task start
- **Notes file freshness**: `int(mtime) > TASK_START`
- **Notes content analysis**:
  - Dollar amount: regex `\$[\d,.]+\s*[BbTtMm]illion` or `[\d,.]+\s*billion`
  - Contractor names: generic company keywords (LLC, Inc, Corp, Lockheed, Raytheon, Boeing, etc.)
  - URLs: presence of `http://` or `https://` patterns
  - Minimum length: ≥200 chars
- **Bookmark check**: "Government Spending Research" folder with ≥3 bookmarks linking to usaspending.gov

## Data Sources

All data is publicly available:
- USASpending.gov: https://www.usaspending.gov/
- FPDS-NG: https://www.fpds.gov/
- Data.gov datasets: https://catalog.data.gov/
- USASpending Advanced Search: https://www.usaspending.gov/search/

## Schema Reference

```sql
-- Bookmark folder
SELECT id FROM moz_bookmarks WHERE title='Government Spending Research' AND type=2;

-- USASpending visits
SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h
JOIN moz_places p ON h.place_id=p.id
WHERE p.url LIKE '%usaspending.gov%' AND h.visit_date > <task_start_us>;
```

## Edge Cases

- Agent may use different fiscal year if FY2023 data not surfaced first — any recent year (2020-2024) is acceptable
- DOD spending totals are large: typically $300B+ in contracts annually
- Top contractors typically include Lockheed Martin, Raytheon, Boeing, General Dynamics, Northrop Grumman
- CSV download may contain hundreds of thousands of rows — even 100 rows is fine
- Notes file can be brief but must include numeric data + sources + contractor names
