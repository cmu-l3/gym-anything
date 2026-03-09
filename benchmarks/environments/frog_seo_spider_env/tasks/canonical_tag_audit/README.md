# Task: Canonical Tag Audit

## Domain Context

**Occupation**: SEO Manager (Marketing Manager — "Supervising organic search strategy and auditing site health")
**Industry**: Digital Marketing / Technical SEO
**Tool Feature**: Screaming Frog Canonicals Tab

The `<link rel="canonical">` tag signals to search engines which URL is the "master" version of a page when multiple URLs have the same or similar content. Incorrect canonical implementation is one of the most common causes of duplicate content penalties and ranking dilution. SEO Managers audit canonical tags using Screaming Frog to identify: self-referencing canonicals (expected on final URLs), canonicalized pages (should not receive PageRank), missing canonicals (risk of duplicate content indexing), and canonical chains (A canonicals to B which canonicals to C — these should be collapsed).

## Goal

Crawl `https://crawler-test.com/` and:

1. **Export the canonical tag data** as a CSV to `~/Documents/SEO/exports/` — must contain page URLs and their canonical URL values (the `<link rel="canonical">` href values)
2. **Write a canonical tag audit report** at `~/Documents/SEO/reports/canonical_report.txt` with:
   - Count of pages with self-referencing canonical tags (canonical = page URL)
   - Count of pages canonicalized to a different URL
   - Count of pages with missing canonical tags
   - Any canonical chains found
   - Prioritized recommendations

## What Success Looks Like

- SF has crawled `crawler-test.com`
- A CSV in `~/Documents/SEO/exports/` contains canonical data: source URL + canonical URL column
- CSV has ≥10 rows (enough pages to distinguish canonical types)
- Text report at `~/Documents/SEO/reports/canonical_report.txt` has ≥200 bytes
- Report contains counts for multiple canonical issue categories

## Verification Strategy

1. Find CSVs in `~/Documents/SEO/exports/` created after task start
2. Identify canonical CSV: check for "Canonical" column or "Canonical Link Element" column
3. Count rows with canonical data
4. Verify target domain in CSV
5. Check text report for numeric counts and canonical-specific terms

## SF Feature Details

**To access canonical data in Screaming Frog:**
- After crawl, click the "Canonicals" tab
- The tab shows all pages with canonical information
- Export via right-click → Export, or use Bulk Export options

**Key Canonical Export Columns:**
- `Address` — the page URL
- `Canonical Link Element 1` — the canonical URL specified by the page
- `Type` — "Contains Canonical", "Missing", etc.
- `Self Referencing` — TRUE/FALSE

## Anti-Gaming Notes

- Task start timestamp recorded
- CSVs must be created after task start
- "Canonical Link Element" column must be present
- Report must contain counts (numbers) and canonical terminology
