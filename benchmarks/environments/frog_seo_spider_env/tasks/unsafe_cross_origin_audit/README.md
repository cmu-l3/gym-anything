# Unsafe Cross-Origin Link Security Audit (`unsafe_cross_origin_audit@1`)

## Overview
This task evaluates the agent's ability to perform a specific web security audit using Screaming Frog's **Security** tab. The agent must identify external links that open in a new tab (`target="_blank"`) but are missing the `rel="noopener"` or `rel="noreferrer"` attribute, which exposes the site to "Reverse Tabnabbing" attacks.

## Rationale
**Why this task is valuable:**
- **Security Awareness**: Tests the ability to audit for "Reverse Tabnabbing" (a real-world security vulnerability where a malicious target page can hijack the referring page).
- **Feature Specificity**: Requires navigating the **Security** tab and understanding its specific filters (distinct from standard SEO tabs like Internal/External).
- **Data Interpretation**: The agent must identify *links* (Inlinks) that trigger the security warning, not just pages.
- **Real-world Hygiene**: Modern web audits routinely flag this issue for remediation.

**Real-world Context:** A Web Security Team has flagged a potential vulnerability on the company's test site. They need a detailed list of all external links that open in a new window without the proper `rel="noopener"` security attribute, so developers can patch them in the CMS.

## Task Description

**Goal:** Crawl `https://crawler-test.com/` and identify all **Unsafe Cross-Origin Links** (links with `target="_blank"` missing `noopener`), then export the findings to a CSV.

**Starting State:**
- Screaming Frog SEO Spider is open.
- No crawl has been started.
- The URL bar is empty.

**Expected Actions:**
1.  Enter `https://crawler-test.com/` in the URL bar and start the crawl.
2.  Wait for the crawl to complete.
3.  Navigate to the **Security** tab in the main interface.
4.  Use the filter dropdown to select **"Unsafe Cross-Origin Links"**.
5.  Export the filtered list of unsafe links to `~/Documents/SEO/exports/unsafe_links.csv`.
    - *Note:* The export should contain the source URL (Address) and the unsafe link details.
6.  Generate a summary text file at `~/Documents/SEO/reports/security_summary.txt` stating the total number of unsafe links found.

**Final State:**
- A CSV file exists at `~/Documents/SEO/exports/unsafe_links.csv` containing the unsafe link data.
- A text file exists at `~/Documents/SEO/reports/security_summary.txt` with a numeric count.

## Verification Strategy

### Primary Verification: CSV Content Analysis
1.  **File Existence**: Verify `~/Documents/SEO/exports/unsafe_links.csv` exists and was created after task start.
2.  **Content Match**:
    - The CSV must contain `crawler-test.com` URLs.
    - The CSV must contain known unsafe link targets (e.g., links to `external` or test pages provided by `crawler-test.com`).
    - The export format should match the Security tab export (containing columns like "Address", "Destination", "Target", "Rel" or similar).
3.  **Row Count**: Verify the CSV contains at least 1 data row (the test site definitely contains these vulnerabilities).

### Secondary Verification: Report Consistency
1.  **Report Check**: Verify `~/Documents/SEO/reports/security_summary.txt` exists.
2.  **Number Validity**: Parse the number in the text file and compare it to the row count in the CSV (allowing for header rows). They should match.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Crawl Completed | 20 | Evidence of `crawler-test.com` crawl in logs/files |
| Security CSV Created | 30 | File exists in correct location |
| Correct Security Filter | 30 | CSV contains specific "Unsafe Cross-Origin" data (validated by content/headers) |
| Report Created | 10 | Summary text file exists |
| Data Consistency | 10 | Count in report matches CSV data |
| **Total** | **100** | |

**Pass Threshold**: 80 points (Must produce the correct CSV export).