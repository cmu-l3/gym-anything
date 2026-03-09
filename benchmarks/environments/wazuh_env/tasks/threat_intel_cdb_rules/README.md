# Task: threat_intel_cdb_rules

## Domain Context

**Primary users**: Information Security Engineers
**GDP footprint**: $2.9B (highest Wazuh occupational segment)
**Real workflow**: "Essential for log aggregation, threat detection, and incident response monitoring across the enterprise"

Threat intelligence operationalization is a core daily activity for security engineers. When an ISAC or threat feed shares IOC data, engineers must rapidly integrate it into detection tooling. This task simulates the real workflow of converting external threat intelligence into SIEM detection rules.

## Task Overview

Integrate a real Feodo Tracker botnet C2 IP blocklist (downloaded from abuse.ch) into Wazuh's detection engine using CDB (Constant Database) lookup lists and custom detection rules.

## Goal / End State

1. A Wazuh CDB list exists at `/var/ossec/etc/lists/` inside the Wazuh manager container, containing >= 5 IP addresses from the Feodo Tracker feed staged at `/tmp/feodotracker_c2_ips.txt`
2. At least one custom rule in `local_rules.xml` uses a `<list>` element to perform a CDB lookup against the malicious IP list
3. The detection rule has severity level >= 9
4. (Bonus) ossec.conf explicitly declares the CDB list in its `<ruleset>` section

## Difficulty: very_hard

The agent must figure out:
- How to convert the raw Feodo Tracker IP list format into Wazuh CDB format (`ip:` per line)
- How to create/upload a CDB list via Wazuh dashboard or API
- How to write a Wazuh rule with `<list lookup="address_match_key" field="srcip">` syntax
- How to reference the CDB list in ossec.conf `<ruleset>` section
- Which Wazuh rule fields are appropriate for network threat intelligence detection

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| CDB list with >= 5 IP entries in /var/ossec/etc/lists/ | 35 | `grep -cE "^[0-9]{1,3}\.[0-9]{1,3}"` on each list file |
| At least 1 rule uses `<list>` CDB lookup | 35 | XML parse local_rules.xml for `<list>` elements |
| CDB rule has level >= 9 | 20 | Extract `level` attribute from rules with `<list>` |
| ossec.conf has list declaration | 10 (bonus) | Grep ossec.conf for `etc/lists` |

**Pass threshold**: 60 points

## Data Source

**Real data**: Feodo Tracker C2 IP Blocklist from abuse.ch
**URL**: `https://feodotracker.abuse.ch/downloads/ipblocklist.txt`
**License**: Free for all use cases
**Content**: Current active botnet C2 IP addresses from Emotet, Trickbot, QakBot, and other banking trojans

## Key Wazuh Concepts

### CDB List Format
```
192.168.1.1:
10.0.0.2:malicious
```

### CDB List in ossec.conf (ruleset section)
```xml
<ruleset>
  <list>etc/lists/malicious-ips</list>
</ruleset>
```

### Rule with CDB Lookup
```xml
<rule id="100020" level="10">
  <if_sid>5500</if_sid>
  <list lookup="address_match_key" field="srcip">etc/lists/malicious-ips</list>
  <description>Connection to known botnet C2 server $(srcip)</description>
  <group>malware,threat_intel,</group>
</rule>
```

## Edge Cases

- The Feodo Tracker file contains comment lines starting with `#` — these must be stripped when creating the CDB list
- CDB list entries require a colon: `192.168.1.1:` (with trailing colon)
- The rule's `field` attribute must match a field that Wazuh actually extracts from the decoded log (e.g., `srcip`, `dstip`)
- After uploading rules via API or dashboard, Wazuh may need to be restarted to compile CDB lists
