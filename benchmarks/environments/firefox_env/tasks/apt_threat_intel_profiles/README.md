# Task: APT Threat Intelligence Profiles

## Overview

**Difficulty**: Very Hard
**Occupation**: Intelligence Analyst
**Domain**: Cybersecurity OSINT / Threat Intelligence

## Background

Intelligence analysts working at government agencies, defense contractors, and enterprise SOCs regularly compile threat actor dossiers from public OSINT sources. This task replicates that workflow: gathering intelligence about two of the world's most sophisticated nation-state threat actors using only publicly available information.

The two groups are:
- **Sandworm** (Voodoo Bear / APT44): Russian GRU threat actor responsible for NotPetya, the Ukraine power grid attacks, and Olympic Destroyer
- **Lazarus Group** (Hidden Cobra / APT38): North Korean DPRK-linked threat actor responsible for the Sony Pictures hack, WannaCry, Bangladesh Bank heist, and Ronin Network theft

## Task Goal

Build research dossiers on both APT groups using public OSINT sources. Organize findings in Firefox bookmarks and produce a written threat intelligence report.

## Success Criteria

### Bookmark Organization
- Bookmark folder "APT Research" must exist in Firefox bookmarks
- Sub-folder "Sandworm" with ≥3 source bookmarks
- Sub-folder "Lazarus Group" (or "Lazarus") with ≥3 source bookmarks
- Bookmarks must include links to authoritative security sources (MITRE, CISA, FBI, vendor blogs)

### History Evidence
- Evidence of visiting attack.mitre.org (MITRE ATT&CK group pages)
- Evidence of visiting at least one government advisory source (cisa.gov, fbi.gov, ic3.gov, or similar)

### Report File
- File: `~/Desktop/threat_intel_report.txt`
- Must contain section headers for both groups
- Must include MITRE ATT&CK technique IDs (format: T followed by 4 digits, e.g., T1059)
- Must include nation-state attribution for each group
- Must include primary target sectors

## Verification Strategy

The verifier checks:
1. Firefox history for authoritative cybersecurity sources (20 pts)
2. "APT Research" bookmark folder exists (15 pts)
3. Sub-folders for Sandworm and Lazarus Group with correct bookmarks (25 pts)
4. Report file exists and was created after task start (15 pts)
5. Report content quality: group names + ATT&CK IDs + attribution keywords (25 pts)

**Pass threshold**: 60/100 points

## Key Public Sources

Agents should use (but are not limited to):
- MITRE ATT&CK Groups: https://attack.mitre.org/groups/
- CISA Advisories: https://www.cisa.gov/news-events/cybersecurity-advisories
- FBI Cyber Division reports: https://www.fbi.gov/investigate/cyber
- US-CERT: https://www.us-cert.cisa.gov/
- Security vendor threat intelligence blogs (CrowdStrike, Mandiant/Google, Recorded Future, etc.)

## Anti-Gaming Notes

- Report file must be created AFTER task start (timestamp check)
- Content must contain actual ATT&CK technique IDs (T-codes), not just "TTPs"
- Bookmark domains must be actual security research sources
- Both group names must appear as section headers, not just incidental mentions
