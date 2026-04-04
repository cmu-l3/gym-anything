# Third-Party Vendor Risk Management Program

## Task Overview

Establish a formal Third-Party Risk Management (TPRM) program in Eramba for First National Capital Bank, registering critical vendors, documenting associated risks, and creating governing policy following the 2023 MOVEit-style supply chain breach risk.

## Professional Context

- **Role**: Third-Party Risk Manager
- **Occupation**: Security Management Specialist (ONET 13-1199.07)
- **Industry**: Banking / Financial Services
- **Organization**: First National Capital Bank ($18B AUM regional bank)
- **Driver**: CRO mandate for TPRM program following supply chain breach wave targeting financial institutions

## Requirements

### 1. Vendor Registry — ≥4 New Critical Third-Party Vendors

Register critical banking vendors not already in the system (AWS and Salesforce are already registered). Examples of plausible critical suppliers for a regional bank:

| Vendor | Description |
|---|---|
| FIS Global | Core banking platform and payment processing |
| Experian | Credit bureau data, KYC/AML screening |
| Jack Henry & Associates | Digital banking, payment rails, and card management |
| Symitar | Credit union lending and member services |
| Fiserv | Core banking, bill payment, and merchant services |
| NCR Atleos | ATM network and cash management |

### 2. Vendor-Associated Risks — ≥4 New Risks with Treatment

For each new vendor, create at least one risk documenting the exposure:
- **Vendor concentration risk** — single vendor providing critical function with no fallback
- **Supply chain attack** — vendor software compromised and used as attack vector
- **SLA breach / business continuity failure** — vendor outage disrupts banking operations
- **Third-party data breach** — vendor holds/processes customer PII and suffers breach
- **Regulatory / compliance risk** — vendor loses certification (SOC 2, PCI-DSS) mid-engagement

Each risk must have a treatment strategy (Accept, Avoid, Mitigate, or Transfer).

### 3. Policy — "Third-Party Risk Management Policy" (Approved)

Create this specific policy with **Approved** status.

### 4. Project — Title Must Contain "Vendor"

Create a project tracking the vendor assessment program (e.g., "Q2 Vendor Risk Assessment Program").

### 5. Policy Exceptions — ≥2 Exceptions with Expiration Dates

Document temporary waivers for vendors not yet meeting TPRM standards:
- Legacy data provider with expiring SOC 2 attestation
- New fintech partner pending security questionnaire completion
- Vendor with outstanding penetration test findings

## Scoring

| Criterion | Points |
|---|---|
| ≥4 new third-party vendors (7.5 pts each) | 30 |
| ≥4 new risks with treatment strategies (7.5 pts each) | 30 |
| "Third-Party Risk Management Policy" with Approved status | 20 |
| Project with "Vendor" in title | 10 |
| ≥2 policy exceptions | 10 |
| **Total** | **100** |
| **Pass threshold** | **60** |

## Access

- URL: http://localhost:8080
- Credentials: admin / Admin2024! (also at `/home/ga/eramba/credentials.txt`)

## Notes

The environment already contains two third-party vendors: "AWS (Amazon Web Services)" and "Salesforce Inc." Your 4+ new vendors must be different organizations. The existing risks and controls from the pre-seeded environment do not count toward this task's scoring.
