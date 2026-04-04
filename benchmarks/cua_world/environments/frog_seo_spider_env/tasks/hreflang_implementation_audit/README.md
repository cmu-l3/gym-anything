# Task: Hreflang Implementation Audit

## Domain Context

**Occupation**: International SEO Specialist (Search Marketing Strategist)
**Industry**: Digital Marketing / International SEO
**Tool Feature**: Screaming Frog Hreflang Tab

Hreflang is an HTML attribute that tells search engines which language/region variant of a page to serve to users in different locales. Incorrect implementation causes international ranking issues: wrong-language pages appearing in search results, duplicate content across locales, and wasted crawl budget. International SEO specialists audit hreflang with tools like Screaming Frog to identify specific error types (missing return links, invalid language codes, non-canonical pages with hreflang, orphaned hreflang).

## Goal

Crawl `https://crawler-test.com/` and:

1. **Export the hreflang data** as a CSV to `~/Documents/SEO/exports/` — must contain page URLs and their hreflang attribute data including language codes
2. **Write a professional hreflang audit report** at `~/Documents/SEO/reports/hreflang_report.txt` including:
   - Unique language codes found (e.g., en, de, fr, x-default)
   - Count of pages with hreflang tags
   - Specific error types present (missing return links, invalid language codes, non-canonical, etc.)
   - Prioritized remediation recommendations

## What Success Looks Like

- SF has crawled `crawler-test.com`
- A CSV in `~/Documents/SEO/exports/` contains hreflang data with language codes (e.g., "en", "de", "fr", "x-default")
- The CSV has ≥5 rows of hreflang attribute data
- A text report at `~/Documents/SEO/reports/hreflang_report.txt` has ≥200 bytes
- The report mentions language codes and specific error types found

## Verification Strategy

1. Find CSVs in `~/Documents/SEO/exports/` created after task start
2. Identify the hreflang CSV: check for "Language" column or hreflang-related columns + language code values
3. Count rows with valid language codes
4. Verify ≥2 unique language codes
5. Check text report exists with minimum content mentioning language codes

## SF Feature Details

**To access hreflang data in Screaming Frog:**
- After crawl, click the "Hreflang" tab (may need to scroll tab bar right)
- If the tab shows "No Data", hreflang checking must be enabled via Configuration → Spider → Advanced → Check Hreflang
- Export via the Hreflang tab → Export (right-click or File menu)

**Key Hreflang Export Columns:**
- `Address` — page URL
- `Language` — hreflang language code (e.g., "en", "de-de", "x-default")
- `Self Referencing` — whether page has a self-referencing hreflang
- `Missing Return Link` — whether the target page returns a hreflang link back
- `Language Code Not Found (Invalid)` — invalid language code flag

## Anti-Gaming Notes

- Task start timestamp recorded
- CSVs must be created after task start
- CSV must contain language codes (not just any CSV)
- Report must mention language codes and errors (not just generic text)
