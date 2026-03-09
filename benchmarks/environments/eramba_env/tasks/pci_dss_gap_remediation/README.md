# PCI-DSS Gap Remediation

## Task Overview

Document 6 QSA audit findings in Eramba as formally treated risks, and build the associated remediation plan for ShopStream Inc., an e-commerce retailer processing $2.3B in annual card transactions.

## Professional Context

- **Role**: PCI-DSS Compliance Manager
- **Occupation**: Compliance Officers (ONET 13-1041.00)
- **Industry**: Retail / E-commerce (Payment Card Industry)
- **Organization**: ShopStream Inc.
- **Driver**: Annual QSA audit identified 6 PCI-DSS compliance gaps requiring formal remediation documentation

## QSA Findings to Document

| # | Requirement | Finding | Severity |
|---|---|---|---|
| 1 | PCI Req 1.2 | Firewall config not reviewed in 6+ months | High |
| 2 | PCI Req 3.4 | Cardholder PAN stored unencrypted in legacy warehouse DB | **Critical** |
| 3 | PCI Req 6.3 | Web app vulnerability scanning is manual, not per-release | High |
| 4 | PCI Req 7.2 | Privileged admin access reviews not done in 12 months | High |
| 5 | PCI Req 10.6 | Security log review is manual / single-analyst dependency | Medium |
| 6 | PCI Req 12.10 | Incident response plan untested for 18 months | High |

## Requirements

### 1. Risk Register — 6 New Risks, All with "Mitigate" Treatment

Create one risk per QSA finding. For every risk, set the treatment strategy to **Mitigate**.

### 2. Internal Controls — ≥3 New Security Services

Addressing the Critical and High findings:
- Quarterly Firewall Configuration Review Procedure
- Cardholder Data (PAN) Encryption Enforcement Program
- Privileged Access Review and Recertification Process
- Automated Vulnerability Scanning for Web Applications

### 3. Project — Title Must Contain "PCI"

Create a project to track the PCI remediation sprint (e.g., "PCI-DSS Gap Remediation Sprint Q2").

### 4. Policy Exceptions — ≥2 Exceptions with Expiration Dates

Formally document risk acceptance for:
- Legacy warehouse database (Req 3.4 — unencrypted PAN storage, migration in progress)
- Manual log review process (Req 10.6 — SIEM procurement pending)

### 5. Security Policy — "Payment Card Data Security Policy" (Draft)

Create this policy with **Draft** status.

## Scoring

| Criterion | Points |
|---|---|
| 6 new risks with Mitigate treatment (6.5 pts each) | 39 |
| ≥3 new internal controls | 21 |
| Project with "PCI" in title | 10 |
| ≥2 policy exceptions | 15 |
| "Payment Card Data Security Policy" (Draft) | 15 |
| **Total** | **100** |
| **Pass threshold** | **60** |

## Access

- URL: http://localhost:8080
- Credentials: admin / Admin2024! (also at `/home/ga/eramba/credentials.txt`)

## Notes

The pre-seeded "Ransomware Attack on Corporate Network" risk already has Mitigate treatment. Your 6 new PCI-DSS risks must be created in addition to all existing records. The QSA findings provided above define the specific risks you must document — use these as the basis for naming and describing each risk.
