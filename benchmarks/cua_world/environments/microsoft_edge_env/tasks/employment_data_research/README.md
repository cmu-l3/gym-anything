# Task: Employment Data Research and Policy Briefing

## Domain Context
Economists and survey researchers regularly compile current economic indicator data from authoritative government sources for policy briefings, forecasting reports, and research publications. This is core professional work: navigating complex government data portals (BLS, FRED, Census), downloading datasets, and synthesizing findings into concise analytical documents.

## Goal
Collect current US labor market data (unemployment rate, nonfarm payrolls, labor force participation) from official government/Fed sources, download associated data files, organize bookmarks into a folder called "Labor Market Data", and produce a policy briefing at `/home/ga/Desktop/labor_briefing.txt`.

## What the Agent Must Figure Out
- Which authoritative sources to use (BLS, FRED, Census — not Google or Wikipedia)
- How to navigate BLS.gov (complex site with many series) to find unemployment rate (U-3 series)
- How to navigate FRED to find nonfarm payrolls (PAYEMS series) and LFPR (CIVPART series)
- How to download data files from these portals (usually CSV or XLS buttons)
- How to create a new Favorites folder in Edge and bookmark pages to it
- How to write a professional policy briefing with exact values and economic interpretation

## Success Criteria
The task is considered complete when:
1. Briefing file exists at `/home/ga/Desktop/labor_briefing.txt`, written after task start
2. Briefing contains a percentage value (unemployment or participation rate)
3. Browser history shows visits to at least one official government source (bls.gov or fred.stlouisfed.org)
4. At least one data file has been downloaded from an official source
5. A bookmark folder named "Labor Market Data" exists with at least 2 bookmarks pointing to authoritative government sites

## Verification Strategy
- **Briefing file**: Exists, modified after task start, contains percentage values, mentions key concepts
- **History**: Query Edge History SQLite for visits to bls.gov, fred.stlouisfed.org, or census.gov
- **Downloads**: Check History downloads table for files from official domains; check ~/Downloads filesystem
- **Bookmarks**: Parse Edge Bookmarks JSON for a "Labor Market Data" folder containing authoritative URLs

## Scoring Breakdown (100 points)
- Briefing file exists and modified after task start: 10 points
- Briefing contains a percentage value (e.g., "4.1%"): 15 points
- Briefing mentions all three indicator names (unemployment, payroll/employment, participation): 15 points
- History shows visits to bls.gov or fred.stlouisfed.org: 25 points
- At least one downloaded data file exists: 20 points
- "Labor Market Data" folder exists in bookmarks with authoritative URLs: 15 points

**Pass threshold**: 65 points

## Why This Is Very Hard
1. Agent must independently identify which government sources to use — not told
2. BLS.gov and FRED have complex navigation — finding the right series requires domain knowledge
3. Downloading from BLS/FRED requires navigating through data selector interfaces
4. Creating a named bookmark folder is a multi-step UI operation in Edge
5. Writing an economic interpretation requires understanding the data context
6. Three independent subtasks (download, bookmark, briefing) must all be completed

## Data Sources (Real)
- BLS Unemployment Rate: https://www.bls.gov/news.release/empsit.htm (monthly news release)
- FRED Unemployment: https://fred.stlouisfed.org/series/UNRATE
- FRED Nonfarm Payrolls: https://fred.stlouisfed.org/series/PAYEMS
- FRED Labor Force Participation: https://fred.stlouisfed.org/series/CIVPART
- BLS Employment Situation: https://www.bls.gov/emp/
