# Task: web_attack_decoder_rules

## Domain Context

**Primary users**: Information Security Analysts
**GDP footprint**: $541M (core SIEM usage occupation)
**Real workflow**: "SIEM platforms are the primary dashboard for security analysts to monitor, detect, and respond to incidents"

Writing custom decoders and detection rules is a frequent activity for SOC analysts extending their SIEM's coverage to new log sources. When a new application or service is added to monitoring, analysts must write decoders to parse its log format and rules to detect attack patterns.

## Task Overview

Create custom Wazuh decoders for nginx access logs and detection rules for SQL injection, path traversal, and command injection attacks, with MITRE ATT&CK technique mappings.

## Goal / End State

1. A custom decoder in `/var/ossec/etc/decoders/local_decoder.xml` that parses nginx access log format (extracting URL, method, status code, source IP fields)
2. At least 3 custom rules in `local_rules.xml`:
   - SQL injection detection: level >= 10
   - Path/directory traversal detection: level >= 10
   - Command injection detection: level >= 9
3. At least one rule has a MITRE ATT&CK technique mapping (e.g., T1190 Exploit Public-Facing Application)
4. `local_decoder.xml` is valid XML

## Difficulty: very_hard

The agent must figure out:
- Wazuh decoder XML syntax (parent/child decoder structure, `<prematch>`, `<regex>`, `<order>` elements)
- How nginx access log format is structured and which regex captures the URL and other fields
- Wazuh rule syntax with `<field name="url">` or `<regex>` for pattern matching
- How to write PCRE2-compatible regex patterns that match attack signatures without causing false positives
- How to add MITRE ATT&CK mappings using `<mitre><id>T1190</id></mitre>` or group classification
- How to upload/save decoders via the Wazuh dashboard or API

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| Custom nginx/web decoder in local_decoder.xml | 20 | Check decoder name or program_name for nginx/http/web keywords; check regex for HTTP patterns |
| >= 3 web attack detection rules | 30 | Parse rules for SQL/traversal/command injection patterns in rule XML text |
| At least one rule level >= 10 | 20 | Extract max level from web attack rules |
| MITRE ATT&CK mapping in >= 1 rule | 15 | Grep for 'mitre', 'T1190', 'att&ck' in rule XML |
| local_decoder.xml is valid XML | 15 | XML parse with root wrapper |

**Pass threshold**: 60 points

## Nginx Access Log Format

```
$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"
```

**Example**:
```
10.0.0.1 - - [14/Jan/2024:10:23:45 +0000] "GET /index.php?id=1' OR '1'='1 HTTP/1.1" 500 1234 "-" "Mozilla/5.0"
10.0.0.2 - - [14/Jan/2024:10:24:01 +0000] "GET /../../etc/passwd HTTP/1.1" 404 512 "-" "curl/7.68.0"
```

## Key Wazuh Concepts

### Decoder Structure
```xml
<decoder name="nginx-access">
  <program_name>nginx</program_name>
  <prematch>^\d+\.\d+\.\d+\.\d+ - </prematch>
  <regex>^(\S+) - \S+ \[\S+ \S+\] "(\w+) (\S+) HTTP[\S]+" (\d+) </regex>
  <order>srcip, http_method, url, http_status</order>
</decoder>
```

### Rule with Field Matching and MITRE
```xml
<rule id="100100" level="10">
  <decoded_as>nginx-access</decoded_as>
  <field name="url">(?i)(select[\s\+]|union[\s\+]|insert[\s\+]|drop[\s\+]|'[\s]*or[\s]*'|1=1|--[\s])</field>
  <description>Web Attack: SQL injection attempt in URL $(url)</description>
  <group>attack,web_attack,sql_injection,mitre_att&amp;ck,</group>
  <mitre>
    <id>T1190</id>
  </mitre>
</rule>
```

### MITRE ATT&CK Technique References
- **T1190**: Exploit Public-Facing Application (SQL injection, XSS, path traversal)
- **T1059**: Command and Scripting Interpreter (command injection)
- **T1083**: File and Directory Discovery (path traversal)

## Edge Cases

- The `<decoded_as>` element requires that the decoder name matches exactly
- Regex in Wazuh uses PCRE2 syntax — test patterns carefully
- The `&` character in XML must be escaped as `&amp;` (e.g., `att&amp;ck` in group names)
- `local_decoder.xml` does not need a root XML element — multiple `<decoder>` elements can be at the top level, but for XML validation the verifier wraps content in `<root>`
