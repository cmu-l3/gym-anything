# Ransomware Incident Post-Mortem Documentation

## Task Overview

Following a LockBit 3.0 ransomware attack, document the incident formally in Eramba, conduct a root-cause analysis, create remediation controls, log emergency exceptions, and launch a recovery project for VertexCloud Technologies.

## Professional Context

- **Role**: Chief Information Security Officer (CISO)
- **Occupation**: Security Management Specialist (ONET 13-1199.07)
- **Industry**: Technology / SaaS
- **Organization**: VertexCloud Technologies (SaaS platform, 3,200 enterprise clients)
- **Incident**: LockBit 3.0 ransomware — initial access via unpatched VPN, 4.2TB encrypted, 72-hour recovery

## Incident Summary

| Attribute | Detail |
|---|---|
| Attack Group | LockBit 3.0 |
| Initial Access Vector | Unpatched CVE in FortiGate VPN appliance |
| Lateral Movement | Pivot from DMZ to backup server via flat network |
| Data Affected | 4.2TB production data + backup data encrypted |
| Ransom Demand | $2.1M (not paid) |
| Recovery Method | Offline cold backup restoration |
| Downtime | 72 hours |

## Requirements

### 1. Security Incident — Title Must Contain "Ransomware"

Document the full incident with:
- Initial access mechanism
- Data scope and business impact
- Recovery actions taken
- Attribution (LockBit 3.0)

### 2. Post-Incident Risks — ≥3 New Risks with Treatment

Root cause gaps that must become formal risks:

| Root Cause Area | Example Risk Title |
|---|---|
| Unpatched perimeter device | Unpatched VPN Appliance Creating External Attack Vector |
| No offline/immutable backups | Backup Storage Vulnerable to Encryption via Ransomware |
| Flat network / no segmentation | Lack of Network Segmentation Enabling Lateral Movement |
| Vendor remote access | Third-Party Remote Access as Ransomware Entry Point |
| Insufficient privileged access monitoring | Unmonitored Admin Account Abuse During Lateral Movement |

Each risk must have a treatment strategy (Accept, Avoid, Mitigate, or Transfer).

### 3. Remediation Controls — ≥4 New Security Services

Controls identified as missing during the incident:
- Immutable Backup Storage with Air-Gap Isolation
- Network Microsegmentation and Zero-Trust Architecture
- Vulnerability and Patch Management SLA Enforcement
- Privileged Access Management (PAM) Solution Deployment
- Incident Response Playbook Testing and Tabletop Exercises

### 4. Emergency Exception Documentation — ≥2 Policy Exceptions

Log security control bypasses made during recovery:
- Emergency admin credentials created without change management ticket
- Temporary firewall rules opened for forensic vendor remote access
- Backup restoration bypassing standard change control process

### 5. Remediation Project — Title Contains "Recovery" or "Ransomware"

Create a project tracking all post-incident remediation work (e.g., "Ransomware Recovery and Hardening Initiative 2025").

## Scoring

| Criterion | Points |
|---|---|
| Security incident with "Ransomware" in title | 20 |
| ≥3 new post-incident risks with treatment strategies | 20 |
| ≥4 new internal controls (remediation controls) | 25 |
| ≥2 policy exceptions (emergency bypass documentation) | 20 |
| Project with "Recovery" or "Ransomware" in title | 15 |
| **Total** | **100** |
| **Pass threshold** | **60** |

## Access

- URL: http://localhost:8080
- Credentials: admin / Admin2024! (also at `/home/ga/eramba/credentials.txt`)

## Notes

The environment already has a "Ransomware Attack on Corporate Network" risk with Mitigate treatment. Your post-incident risks must be new records documenting specific root causes identified during the incident. The existing controls (EDR, Vulnerability Management) do not count toward the 4+ new remediation controls required.
