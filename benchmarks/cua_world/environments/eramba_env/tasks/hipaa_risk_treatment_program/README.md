# HIPAA Risk Treatment Program

## Task Overview

Build and formalize a HIPAA Security Rule compliance program in Eramba for Summit Regional Medical Center, a 350-bed acute care hospital preparing for an HHS Office for Civil Rights (OCR) audit.

## Professional Context

- **Role**: Information Security Officer
- **Occupation**: Security Management Specialist (ONET 13-1199.07)
- **Industry**: Healthcare
- **Organization**: Summit Regional Medical Center
- **Driver**: Mandatory HIPAA risk analysis findings must be documented and treated before OCR audit in 90 days

## Requirements

### 1. Risk Register — ≥5 New Risks, Each with Treatment Strategy

Create risks covering HIPAA threat categories. For each risk, set one of: **Accept**, **Avoid**, **Mitigate**, or **Transfer**.

| Required Category | Example Risk Title |
|---|---|
| Unauthorized PHI access (external) | Unauthorized External Access to Electronic Health Records |
| Ransomware / clinical disruption | Ransomware Encryption of Clinical Systems and EHR Data |
| Improper PHI disposal/transmission | Unencrypted PHI Transmission via Unsecured Email |
| Business associate breach | Third-Party Business Associate Data Breach |
| Employee accidental disclosure | Accidental PHI Disclosure via Misdirected Email |

### 2. Internal Controls — ≥3 New Security Services

Create security service entries representing controls that mitigate identified risks:
- EHR Multi-Factor Authentication Enforcement
- PHI Encryption at Rest and in Transit
- HIPAA Security Awareness Training Program
- Access Review for Privileged EHR Accounts
- Workforce Sanctions Policy Enforcement

### 3. Security Policy — "HIPAA Security Rule Compliance Policy" (Approved)

Create a policy with this exact title and set its status to **Approved**.

### 4. Project — Title Must Contain "HIPAA"

Create a project tracking HIPAA remediation activities (e.g., "HIPAA Risk Assessment Remediation 2025").

### 5. Policy Exceptions — ≥2 Exceptions with Expiration Dates

Document areas where full compliance is deferred:
- Legacy medical devices that cannot yet be encrypted
- Temporary remote access exception for telework clinicians
- Older radiology equipment running unsupported OS

## Scoring

| Criterion | Points |
|---|---|
| ≥5 new risks with treatment strategies set (8 pts each, up to 5) | 40 |
| ≥3 new internal controls | 20 |
| "HIPAA Security Rule Compliance Policy" with Approved status | 20 |
| Project with "HIPAA" in title | 10 |
| ≥2 policy exceptions | 10 |
| **Total** | **100** |
| **Pass threshold** | **60** |

## Access

- URL: http://localhost:8080
- Credentials: admin / Admin2024! (also at `/home/ga/eramba/credentials.txt`)

## Notes

The environment contains pre-seeded risks (Phishing, Ransomware, Insider Threat) and controls (EDR, Vulnerability Management). All new records you create must be in addition to these existing entries.
