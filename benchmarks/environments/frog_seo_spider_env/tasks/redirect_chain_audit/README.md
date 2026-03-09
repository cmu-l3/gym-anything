# Task: Redirect Chain Audit

## Domain Context

**Occupation**: Technical SEO Consultant (Search Marketing Strategist)
**Industry**: Digital Marketing / SEO
**Tool Feature**: Screaming Frog Response Codes tab (3xx filter) + Redirect Chain analysis

Redirect chains — sequences of 3 or more consecutive redirects (A → B → C → D) — are one of the most damaging technical SEO issues. Each hop in a chain adds latency (typically 300-600ms per redirect on mobile), dilutes PageRank passed through the chain, and can cause crawl budget waste. Technical SEO consultants routinely audit redirect chains prior to site migrations to identify chains that can be consolidated to a single direct redirect.

## Goal

Crawl `https://crawler-test.com/` and:

1. **Export all 3xx redirect responses** as a CSV to `~/Documents/SEO/exports/` — columns must include the source URL, status code, and redirect destination URL
2. **Write a redirect analysis report** at `~/Documents/SEO/reports/redirect_report.txt` containing:
   - Total count of redirecting URLs found
   - Count of redirect chains with 3+ hops
   - Which redirect types (301, 302, 307, etc.) were present
   - Specific remediation recommendations

## What Success Looks Like

- Screaming Frog has crawled `crawler-test.com`
- A CSV in `~/Documents/SEO/exports/` contains 3xx redirect data: source URLs, status codes (301/302/etc.), and destination URLs
- The CSV has ≥3 rows of redirect data
- A text report exists at `~/Documents/SEO/reports/redirect_report.txt` with ≥200 characters
- The report contains counts (numbers) and mentions specific redirect issues found

## Verification Strategy

1. Find CSVs in `~/Documents/SEO/exports/` created after task start
2. Identify the redirect CSV: check for "Status Code" column + 3xx values AND "Redirect URL" column
3. Count rows with 3xx status codes (301, 302, 307, 308)
4. Check for text report file at the specified path
5. Verify report has minimum meaningful content (mentions counts, redirect types)

## SF Feature Details

**To get redirect data in Screaming Frog:**
- After crawl completes, click "Response Codes" tab
- Filter: select "3xx" from the dropdown filter
- Export via right-click → Export, or File → Export → Response Codes → Redirection (3xx)

**For redirect chain analysis:**
- Check Reports menu → Redirect Chains
- This shows chains with ≥3 hops specifically

## Key Columns in SF Redirect Export

- `Address` — source URL (the URL that redirects)
- `Status Code` — HTTP status code (301, 302, 307, 308)
- `Status` — text description (Moved Permanently, Found, etc.)
- `Redirect URL` — destination URL

## Anti-Gaming Notes

- Task start timestamp in `/tmp/task_start_time` and `/tmp/task_start_epoch`
- CSVs must be created AFTER task start
- Domain check: CSV must contain `crawler-test.com` URLs
- Report must have minimum length to avoid trivial outputs
