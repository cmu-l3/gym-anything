# Readability and Content Quality Audit (`readability_content_quality_audit@1`)

## Overview
This task requires the agent to configure and execute a **Content Quality Audit** using Screaming Frog SEO Spider's "Readability" analysis features. The agent must enable the non-standard readability metrics (Flesch Reading Ease), crawl a bookstore website, and export the data to identify content that may be too difficult for the average user to read.

## Rationale
**Why this task is valuable:**
- **Advanced Configuration**: Tests the ability to enable optional content analysis features (Readability) that are disabled by default.
- **Content Strategy Focus**: Shifts focus from "Technical SEO" (tags/headers) to "Content Quality", a key aspect of modern "Helpful Content" optimization.
- **Data Interpretation**: Requires handling and exporting metrics that are calculated post-download.
- **Real-world relevance**: Content managers routinely audit legacy content to ensure it meets accessibility standards.

**Real-world Context:** A Content Marketing Manager at an online bookstore wants to ensure that book descriptions are accessible to a general audience. They need a report showing the "Flesch Reading Ease" score for every product page to identify descriptions that are too dense or academic.

## Task Description

**Goal:** Configure Screaming Frog SEO Spider to calculate **Readability** metrics, crawl `https://books.toscrape.com/`, and export a Content Quality report containing Flesch Reading Ease scores.

**Starting State:**
- Screaming Frog SEO Spider is open and initialized.
- Default settings are active (Readability analysis is **OFF** by default).
- No crawl is in progress.

**Expected Actions:**
1. **Configure Readability**: Navigate to the configuration settings (e.g., `Configuration > Content > Spelling & Grammar / Readability`) and **Enable Readability** analysis. Ensure "Flesch Reading Ease" is selected.
2. **Crawl the Site**: Enter `https://books.toscrape.com/` and start the crawl.
   - *Note*: You may limit the crawl to 50-100 URLs to save time, as long as you get product pages.
3. **Verify Data**: Navigate to the **Content** tab and verify that columns like "Flesch Reading Ease" are populated.
4. **Export Data**: Export the content analysis data to a CSV file named `readability_audit.csv` in `~/Documents/SEO/exports/`.
5. **Analyze**: Create a text file at `~/Documents/SEO/reports/hardest_to_read.txt` containing the URL of the page with the **lowest** Flesch Reading Ease score found.

**Final State:**
- A CSV file `~/Documents/SEO/exports/readability_audit.csv` exists containing URLs and their Readability scores.
- A report `~/Documents/SEO/reports/hardest_to_read.txt` exists with a valid URL from the crawl.

## Verification Strategy

### Primary Verification: CSV Content Analysis
1. **File Existence**: Check for `readability_audit.csv` created after task start.
2. **Feature Validation**: Verify the CSV contains the "Flesch Reading Ease" column. This proves the feature was enabled (it is not present in standard exports).
3. **Data Validation**: Verify the column contains numeric data for `books.toscrape.com` URLs.

### Secondary Verification: Report Check
1. **Report Existence**: Check for `hardest_to_read.txt`.
2. **Content Check**: Verify the file contains a URL from the target domain.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **CSV Export Created** | 30 | A CSV file exists in the correct export directory. |
| **Readability Configured** | 40 | The CSV contains "Flesch Reading Ease" column. |
| **Data Populated** | 20 | The Readability column contains non-zero data. |
| **Analysis Report** | 10 | The text report identifies a specific URL. |
| **Total** | **100** | |

Pass Threshold: 70 points