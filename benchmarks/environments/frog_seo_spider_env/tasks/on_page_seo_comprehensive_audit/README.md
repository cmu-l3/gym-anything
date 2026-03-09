# Task: On-Page SEO Comprehensive Audit

## Domain Context

**Occupation**: Search Marketing Strategist (primary Screaming Frog user, GDP=$10.9B)
**Industry**: Digital Marketing / E-commerce SEO
**Tool Features**: Multiple Screaming Frog tabs — Page Titles, Meta Description, H1 + multiple exports

Search Marketing Strategists spend a substantial portion of their working time producing on-page SEO audits. A complete on-page audit covers the four canonical ranking signals: page title tags (critical for click-through rate in SERPs), meta descriptions (influence CTR), H1 tags (primary on-page keyword signal), and image alt text. For an e-commerce site with hundreds of product pages, these elements need systematic review — not page-by-page, but via a crawl-and-audit workflow with Screaming Frog that identifies patterns across the entire catalog in minutes.

## Goal

Crawl `https://books.toscrape.com/` (at least 100 pages) and produce **three separate CSV exports plus one written summary**:

1. **Page Titles CSV** → `~/Documents/SEO/exports/`: columns include `Title 1`, `Title 1 Length`
2. **Meta Descriptions CSV** → `~/Documents/SEO/exports/`: columns include `Meta Description 1`, `Meta Description 1 Length`
3. **H1 Tags CSV** → `~/Documents/SEO/exports/`: columns include `H1-1`
4. **Audit Summary** → `~/Documents/SEO/reports/on_page_audit.txt`: issue counts for each category + recommendations

## What Success Looks Like

- SF has crawled `books.toscrape.com` with ≥100 pages
- Three separate CSV files in `~/Documents/SEO/exports/` (created after task start) covering the three SEO elements
- OR: One comprehensive CSV that contains all three element types (Title 1 + Meta Description 1 + H1-1 together)
- Text summary with counts for each issue category and recommendations

## Verification Strategy

1. Find all CSVs in `~/Documents/SEO/exports/` created after task start
2. Identify page titles CSV: has "Title 1" and "Title 1 Length" columns
3. Identify meta descriptions CSV: has "Meta Description 1" column
4. Identify H1 CSV: has "H1-1" column
5. (All three can be in a single comprehensive export too)
6. Count pages covered across all exports
7. Check text report for counts and recommendations
8. Verify domain is `books.toscrape.com`

## SF Feature Details

**To export specific on-page element tabs in SF:**
- Page Titles: Click "Page Titles" tab → Export
- Meta Description: Click "Meta Description" tab → Export
- H1: Click "H1" tab → Export
- OR: Export "All Internal" from File menu → includes all columns

**Key Column Names:**
- Page Titles tab: `Address`, `Title 1`, `Title 1 Length`, `Title 1 Pixel Width`, `Title 2`...
- Meta Description tab: `Address`, `Meta Description 1`, `Meta Description 1 Length`, `Meta Description 2`...
- H1 tab: `Address`, `H1-1`, `H1-1 Length`, `H1-2`...

## Anti-Gaming Notes

- All CSVs must be modified after task start
- Domain check: `books.toscrape.com` must be in CSV URLs
- The comprehensive internal export is acceptable if it contains all required columns
- Report must mention multiple issue categories with counts
