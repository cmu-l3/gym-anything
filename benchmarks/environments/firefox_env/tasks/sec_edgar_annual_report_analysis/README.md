# Task: sec_edgar_annual_report_analysis

## Overview

**Environment**: firefox_env
**Difficulty**: Hard
**Occupation**: Financial Analyst / Securities Analyst
**Domain**: Financial Research, SEC Regulatory Filings

A financial analyst performing due diligence research uses SEC EDGAR — the SEC's electronic filing system — to review annual reports (10-K filings) for major technology companies. This is a core task in equity research: locating official SEC filings, extracting key financial data and risk disclosures, and organizing findings for client review.

## Goal

Research the most recent 10-K annual reports for three major technology companies on SEC EDGAR, extract key data, and save findings to a structured JSON file.

**Target companies**:
- **Microsoft Corporation** (CIK: 0000789019) — fiscal year ending June 2024
- **Apple Inc.** (CIK: 0000320193) — fiscal year ending September 2023 or September 2024
- **Alphabet Inc.** (CIK: 0001652044) — fiscal year ending December 2023

**Required output**: `~/Documents/edgar_analysis.json`

```json
{
  "microsoft": {
    "filing_date": "YYYY-MM-DD",
    "risk_factor_count": <integer>,
    "revenue_billions": <number>
  },
  "apple": {
    "filing_date": "YYYY-MM-DD",
    "risk_factor_count": <integer>,
    "revenue_billions": <number>
  },
  "alphabet": {
    "filing_date": "YYYY-MM-DD",
    "risk_factor_count": <integer>,
    "revenue_billions": <number>
  }
}
```

**Required bookmarks**: Create a Firefox bookmark folder named "SEC EDGAR Research" containing at least one EDGAR page for each company (3+ bookmarks).

## Success Criteria

1. Visited SEC EDGAR (sec.gov) to research each of the 3 companies
2. Created `~/Documents/edgar_analysis.json` during this task (file is fresh)
3. JSON file contains all 3 company keys with required fields
4. Filing dates are plausible (2023–2024 range, ISO format)
5. Risk factor counts are plausible (≥5 risk factors per company)
6. Revenue figures are plausible (in expected ranges for these mega-cap companies)
7. "SEC EDGAR Research" bookmark folder exists with ≥3 EDGAR bookmarks

## Verification Strategy

- **History check**: Verify sec.gov domains appear in Firefox history after task start
- **File freshness**: `edgar_analysis.json` must be created/modified after task start timestamp
- **JSON validity**: Parse and validate structure + all required fields
- **Date plausibility**: Filing dates in range 2022-01-01 to 2025-12-31, ISO format
- **Risk factor count plausibility**: Each company ≥5, ≤250 (typical 10-K has 20-60 risk factors)
- **Revenue plausibility**:
  - Microsoft FY2024: ~$245B
  - Apple FY2023/2024: ~$381B / ~$391B
  - Alphabet FY2023: ~$308B
  - Accepted range: ±30% of expected values (accepts older filings)
- **Bookmark folder**: Check Firefox places.sqlite for "SEC EDGAR Research" folder with sec.gov URLs

## Data Sources

All data is publicly available from SEC EDGAR:
- EDGAR full-text search: https://efts.sec.gov/LATEST/search-index?q=...
- EDGAR company search: https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany
- Direct CIK access: https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=0000789019&type=10-K

## Schema Reference (places.sqlite)

```sql
-- Bookmark folder
SELECT id FROM moz_bookmarks WHERE title='SEC EDGAR Research' AND type=2;

-- SEC.gov visits
SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h
JOIN moz_places p ON h.place_id=p.id
WHERE p.url LIKE '%sec.gov%' AND h.visit_date > <task_start_us>;
```

## Edge Cases

- Agent may find filing index pages without reading the actual 10-K document — that's acceptable
- Revenue in billions (not millions) — agent must convert if reading raw SEC figures
- Risk factor count: number of distinct risk factor headings in Item 1A section
- Multiple 10-K filings may exist; should use most recent one
- EDGAR full-text search vs. direct company page — either approach is valid
