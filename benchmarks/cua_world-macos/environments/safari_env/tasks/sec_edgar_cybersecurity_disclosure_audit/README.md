# sec_edgar_cybersecurity_disclosure_audit

## Domain Context

Financial compliance analysts at asset management firms routinely research how publicly traded companies — especially systemically important financial institutions (SIFIs) — disclose material cybersecurity risks in their annual 10-K filings with the SEC. Since the SEC's 2023 cybersecurity disclosure rules, Item 1A (Risk Factors) and the new Item 1C (Cybersecurity) sections have become critical inputs for portfolio risk assessments, proxy advisors, and regulatory stress-test models.

## Goal

Retrieve the five largest U.S. banks' most recent 10-K filings from SEC EDGAR and extract cybersecurity risk disclosure data into a structured JSON file at `~/Documents/edgar_cybersecurity_audit.json`.

## Occupation

**Financial Compliance Analysts / Investment Risk Researchers**  
Industry: Finance / Banking / Asset Management

## Difficulty: very_hard

The description gives only the professional goal. The agent must:
- Independently locate each bank's CIK on EDGAR
- Navigate EDGAR's filing search to find the most recent 10-K
- Locate the Item 1A risk factor section and identify cybersecurity-specific text
- Extract a 100+ word verbatim excerpt demonstrating real cybersecurity risk language
- Capture filing metadata (CIK, fiscal year end, filing date)
- Produce a correctly structured JSON output

## Required Output

**File**: `~/Documents/edgar_cybersecurity_audit.json`  
**Format**: JSON list of objects, one per bank:

```json
[
  {
    "cik": "0000019617",
    "company_name": "JPMorgan Chase & Co.",
    "fiscal_year_end": "2023-12-31",
    "filing_date": "2024-02-16",
    "cybersecurity_risk_factor_excerpt": "We face significant cybersecurity risks... [100+ words verbatim from Item 1A]"
  },
  ...
]
```

## Required Banks

| Bank | Notes |
|---|---|
| JPMorgan Chase & Co. | Largest by assets |
| Bank of America Corp. | |
| Wells Fargo & Company | |
| Citigroup Inc. | |
| Goldman Sachs Group Inc. | |

## Verification Strategy

| Criterion | Points | Details |
|---|---|---|
| ≥1 bank entry found | 15 | At least one bank object matched in output |
| EDGAR visited | 15 | sec.gov must appear in Safari history |
| ≥3 banks complete | 25 | All 5 required fields + 100-word cyber excerpt |
| ≥4 banks complete | 25 | — |
| All 5 banks complete | 20 | — |
| **Pass threshold** | **70** | |

A bank entry is "complete" when it contains: `cik`, `company_name`, `fiscal_year_end`, `filing_date`, and a `cybersecurity_risk_factor_excerpt` of ≥100 words that includes recognisable cybersecurity terminology (e.g., "cybersecurity", "data breach", "information security", "ransomware").

## Adversarial Robustness

- **EDGAR gate**: Score=0 if sec.gov not visited — agent cannot fabricate excerpts without visiting the source
- **Post-setup timestamp**: Output file must be newer than task start
- **Excerpt length + keyword check**: Prevents placeholder or non-cybersecurity text

## Edge Cases

- The SEC modernised its cybersecurity disclosure requirements in 2023; filings from 2024 onward have an explicit "Item 1C: Cybersecurity" section in addition to Item 1A risk factors. Either section's content is acceptable.
- Some banks file under multiple CIKs for holding company vs. operating bank subsidiary — the holding company's 10-K is the correct target.
- Goldman Sachs fiscal year end is December 31; verify the 10-K is annual (not 10-Q).
