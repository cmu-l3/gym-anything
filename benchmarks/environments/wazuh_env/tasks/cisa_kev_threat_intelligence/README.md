# Task: CISA KEV Threat Intelligence Integration

## Overview

**Difficulty**: Very Hard
**Timeout**: 600 seconds | **Max Steps**: 80
**Primary Occupation**: Threat Intelligence Engineer / Information Security Engineer

This task simulates a real threat intelligence integration workflow where the CISA Known Exploited Vulnerabilities (KEV) catalog is integrated into Wazuh's detection pipeline. This is a standard enterprise SOC task — maintaining an up-to-date KEV-based detection capability is a CISA recommended practice for all organizations.

## Domain Context

The **CISA Known Exploited Vulnerabilities Catalog** is maintained by the U.S. Cybersecurity and Infrastructure Security Agency. It lists CVEs that have confirmed active exploitation in the wild. Organizations are required to patch KEV entries within 2-3 weeks if in federal systems, and it's best practice for all enterprises.

Integrating KEV data into a SIEM enables detection of:
- Systems reporting vulnerable software versions (via vulnerability scanning)
- Network traffic referencing known exploited CVE identifiers
- Exploitation attempts matching KEV entries

## Data Source

**Real data**: The CISA KEV catalog is downloaded from:
```
https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json
```

The JSON structure:
```json
{
  "title": "CISA Known Exploited Vulnerabilities Catalog",
  "catalogVersion": "2024.01.28",
  "dateReleased": "2024-01-28T00:00:00.0000000Z",
  "count": 1051,
  "vulnerabilities": [
    {
      "cveID": "CVE-2024-21762",
      "vendorProject": "Fortinet",
      "product": "FortiOS",
      "vulnerabilityName": "Fortinet FortiOS Out-of-Bound Write Vulnerability",
      "dateAdded": "2024-02-09",
      "shortDescription": "...",
      "requiredAction": "Apply mitigations...",
      "dueDate": "2024-03-01",
      "knownRansomwareCampaignUse": "Known"
    }
  ]
}
```

## Starting State

- Real CISA KEV catalog downloaded and staged at `/tmp/cisa_kev.json`
- No CVE-based CDB lists exist in `/var/ossec/etc/lists/`
- No rules using CDB lookup for KEV data
- Vulnerability detection may not be configured

## Goal (End State)

1. **CDB list** with ≥10 CVE IDs from the KEV catalog in `/var/ossec/etc/lists/` (format: `CVE-YYYY-NNNNN:`)
2. **≥1 detection rule** using `<list>` element to look up CVE identifiers against the CDB list
3. **Vulnerability detection module** enabled in ossec.conf
4. **Integration report** at `/home/ga/Desktop/kev_integration_report.txt` (≥600 chars)

## Scoring (100 points total)

| Criterion | Points |
|-----------|--------|
| CDB list with ≥10 CISA KEV CVE IDs | 30 |
| ≥1 detection rule using CDB list lookup (`<list>` element) | 25 |
| Vulnerability detection module enabled in ossec.conf | 20 |
| Integration report ≥600 chars with CISA KEV references | 25 |

**Pass threshold**: 65 points
**Score cap**: If report missing and score ≥65, cap at 64

## Key Wazuh Concepts

### CDB List Format
Each line is `KEY:` (with trailing colon for simple presence lookup):
```
CVE-2024-21762:
CVE-2023-46805:
CVE-2024-21887:
CVE-2023-22515:
CVE-2023-44487:
CVE-2023-23397:
CVE-2023-20198:
CVE-2024-1709:
CVE-2024-21338:
CVE-2023-46747:
```

### Creating CDB from KEV JSON (Python helper)
```python
import json

with open('/tmp/cisa_kev.json') as f:
    data = json.load(f)

with open('/var/ossec/etc/lists/cisa-kev-cves', 'w') as f:
    for vuln in data['vulnerabilities'][:50]:  # First 50 KEV entries
        f.write(f"{vuln['cveID']}:\n")
```

### Declaring CDB List in ossec.conf
```xml
<ruleset>
  <list>etc/lists/cisa-kev-cves</list>
</ruleset>
```

### Detection Rule Using CDB Lookup
```xml
<rule id="100090" level="15">
  <if_sid>0</if_sid>
  <list field="cve" lookup="match_key">etc/lists/cisa-kev-cves</list>
  <description>CISA KEV: Actively exploited vulnerability detected - $(cve)</description>
  <group>vulnerability,threat_intel,cisa_kev</group>
  <mitre><id>T1190</id></mitre>
</rule>
```

The `<list>` element performs a CDB lookup: if the field value matches a key in the CDB file, the rule fires.

### Vulnerability Detection Module (ossec.conf)
```xml
<wodle name="syscollector">
  <disabled>no</disabled>
  <interval>1h</interval>
  <os>yes</os>
  <hardware>yes</hardware>
  <packages>yes</packages>
  <ports all="no">yes</ports>
  <processes>yes</processes>
</wodle>

<wodle name="vulnerability-detector">
  <disabled>no</disabled>
  <interval>5m</interval>
  <min_full_scan_interval>6h</min_full_scan_interval>
  <run_on_start>yes</run_on_start>
  <provider name="nvd">
    <enabled>yes</enabled>
    <update_interval>1h</update_interval>
  </provider>
</wodle>
```

## Files Modified

- `/var/ossec/etc/lists/cisa-kev-cves` (or similar name) — CDB list with KEV CVE IDs
- `/var/ossec/etc/ossec.conf` — CDB list declaration + vulnerability detector wodle
- `/var/ossec/etc/rules/local_rules.xml` — Detection rule with `<list>` lookup
- `/home/ga/Desktop/kev_integration_report.txt` — Integration design documentation
