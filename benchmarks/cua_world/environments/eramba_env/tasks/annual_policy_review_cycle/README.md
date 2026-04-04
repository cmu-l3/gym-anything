# Annual Information Security Policy Review Cycle

## Task Overview

Execute the annual information security policy review cycle for Meridian Life Insurance Group, creating a comprehensive policy framework, registering critical IT assets, documenting non-compliance exceptions, and launching the review tracking project.

## Professional Context

- **Role**: Chief Compliance Officer
- **Occupation**: Compliance Officers (ONET 13-1041.00)
- **Industry**: Insurance / Financial Services
- **Organization**: Meridian Life Insurance Group ($4.2B multi-line insurance carrier, 38 states)
- **Driver**: Annual policy review required by NAIC Model Audit Rule (MAR) and board-approved information security program charter

## Requirements

### 1. Security Policies — ≥5 New Policies with Mixed Statuses

Create policies covering domains not already in the system (Acceptable Use Policy and Password Management Policy already exist).

| Policy | Status | Domain |
|---|---|---|
| Data Governance and Classification Policy | **Approved** | Data governance |
| Access Management and Identity Policy | **Approved** | Access control |
| Business Continuity and Disaster Recovery Policy | **Draft** | BC/DR |
| Cryptography and Key Management Policy | **Draft** | Cryptography |
| [Your choice — e.g., Risk Management Policy, Vendor Management Policy, etc.] | Any | Any domain |

**Required:** At least 2 with status **Approved** AND at least 2 with status **Draft**.

### 2. IT Assets — ≥3 New Asset Records

Register critical Meridian Life systems that the policies govern:
- Policy Administration System (PAS)
- Customer Portal / Self-Service Platform
- Claims Processing Platform
- Enterprise Data Warehouse
- Actuarial Modeling Workstation
- Partner Integration Gateway

### 3. Policy Exceptions — ≥3 Exceptions with Expiration Dates

Formally document non-compliant systems:
- Legacy claims processing system exempt from data encryption policy (hardware refresh in 6 months)
- Actuarial workstation running Windows 2016 Server exempt from OS support policy (migration planned)
- Partner integration server exempt from MFA requirement (third-party system, waiver pending)
- Customer portal pending security testing waiver until penetration test completed

### 4. Project — Title Contains "Policy" or "Audit"

Create a project tracking the review cycle (e.g., "Annual Information Security Policy Review Cycle 2025" or "Q1 Compliance Audit and Policy Refresh").

### 5. Touch an Existing Policy

Review one of the pre-existing policies (Acceptable Use Policy or Password Management Policy) — update its description or any available field to reflect that it was reviewed during the annual cycle.

## Scoring

| Criterion | Points |
|---|---|
| ≥5 new security policies (7 pts each) | 35 |
| New policies include ≥2 Approved AND ≥2 Draft | 15 |
| ≥3 new IT asset records | 20 |
| ≥3 policy exceptions | 20 |
| Project with "Policy" or "Audit" in title | 10 |
| **Total** | **100** |
| **Pass threshold** | **60** |

## Access

- URL: http://localhost:8080
- Credentials: admin / Admin2024! (also at `/home/ga/eramba/credentials.txt`)

## Notes

The environment already contains two policies (Acceptable Use Policy, Password Management Policy — both Approved) and two security controls (EDR, Vulnerability Management). Your 5 new policies must be in addition to these existing records. The assets module may be accessible from a different URL pattern — check the Eramba navigation for "Assets" or similar.
