# Task: Multi-Source Decoder Pipeline

## Overview

**Difficulty**: Very Hard
**Timeout**: 600 seconds | **Max Steps**: 90
**Primary Occupation**: Information Security Engineer / Detection Engineer

This task simulates onboarding two new infrastructure components (nginx web server and PostgreSQL database) into an existing Wazuh SIEM deployment. The agent must build the complete log ingestion and detection pipeline for both sources, including decoder chains, detection rules, ossec.conf configuration, and group-level policy.

## Domain Context

Real SOC environments constantly onboard new log sources. Each new source requires:
1. A **decoder** to parse the raw log format into structured fields
2. **Rules** that reference the decoded fields to detect threats
3. **ossec.conf** localfile entries pointing Wazuh to the log files
4. **Group agent.conf** entries so new agents in the group automatically get the config

This is a core skill for Information Security Engineers building out SIEM detection coverage.

## Starting State

- **Sample nginx log** staged at `/var/log/nginx/access.log` (real nginx combined log format)
- **Sample PostgreSQL log** staged at `/var/log/postgresql/postgresql-14-main.log` (real PostgreSQL log format)
- No nginx or PostgreSQL decoders in `local_decoder.xml`
- No nginx or PostgreSQL detection rules in `local_rules.xml`
- `ossec.conf` has no localfile entries for these sources
- `web-servers` group agent.conf is minimal (no log monitoring config)

## Log Format Reference

### Nginx Combined Log Format (real format)
```
192.168.1.100 - jsmith [28/Jan/2024:10:15:22 +0000] "GET /index.html HTTP/1.1" 200 4520 "-" "Mozilla/5.0"
10.0.0.15 - - [28/Jan/2024:10:15:45 +0000] "GET /api/users?id=1 UNION SELECT-- HTTP/1.1" 200 1234 "-" "sqlmap/1.7.6"
```
Fields: `$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"`

### PostgreSQL Log Format (real format)
```
2024-01-28 10:15:30.789 UTC [12346] unknown@appdb FATAL: password authentication failed for user "admin"
2024-01-28 10:16:30.555 UTC [12353] appuser@appdb ERROR: permission denied for table users
```
Fields: `timestamp timezone [pid] user@database severity: message`

## Goal (End State)

1. **Nginx decoder pair**: parent decoder matching nginx format + child decoder extracting srcip, HTTP method, URL, status code
2. **PostgreSQL decoder pair**: parent + child extracting database, user, event severity
3. **≥3 detection rules**: ≥1 for nginx attacks (SQL injection/scanner/path traversal), ≥1 for PostgreSQL violations (auth failures/unauthorized access)
4. **ossec.conf localfiles**: entries for `/var/log/nginx/` and `/var/log/postgresql/`
5. **web-servers agent.conf**: updated with monitoring configuration for group members

## Scoring (100 points total)

| Criterion | Points |
|-----------|--------|
| Nginx parent + child decoder with field extraction | 20 |
| PostgreSQL parent + child decoder with field extraction | 20 |
| ≥3 detection rules covering nginx attacks AND PostgreSQL access | 25 |
| ossec.conf localfile entries for nginx AND PostgreSQL | 15 |
| web-servers group agent.conf updated | 20 |

**Pass threshold**: 60 points

## Key Wazuh Concepts

### Decoder Structure (Parent + Child)
```xml
<!-- Parent: matches the log prefix -->
<decoder name="nginx">
  <program_name>nginx</program_name>
</decoder>

<!-- Alternative parent using prematch -->
<decoder name="nginx-access">
  <prematch>^\d+\.\d+\.\d+\.\d+ \S+ \S+ \[</prematch>
</decoder>

<!-- Child: extracts fields from matched lines -->
<decoder name="nginx-access-fields">
  <parent>nginx-access</parent>
  <regex>^(\d+\.\d+\.\d+\.\d+) \S+ \S+ \[\S+ \S+\] "(\w+) (\S+) \S+" (\d+)</regex>
  <order>srcip,http_method,url,status</order>
</decoder>
```

### PostgreSQL Decoder
```xml
<decoder name="postgresql">
  <prematch>^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \w+ \[\d+\]</prematch>
</decoder>

<decoder name="postgresql-auth">
  <parent>postgresql</parent>
  <regex>\[\d+\] (\S+)@(\S+) (\w+): (.+)</regex>
  <order>dstuser,db_name,log_level,extra_data</order>
</decoder>
```

### Detection Rules
```xml
<!-- SQL Injection via nginx -->
<rule id="100080" level="12">
  <decoded_as>nginx-access-fields</decoded_as>
  <url_match>UNION|SELECT|INSERT|DROP|--</url_match>
  <description>Possible SQL injection attempt via nginx (T1190)</description>
  <mitre><id>T1190</id></mitre>
</rule>

<!-- PostgreSQL brute force -->
<rule id="100085" level="10" frequency="5" timeframe="60">
  <if_matched_sid>100084</if_matched_sid>
  <description>PostgreSQL brute force: multiple authentication failures</description>
  <same_source_ip />
</rule>
```

### ossec.conf localfile entries
```xml
<localfile>
  <log_format>apache</log_format>
  <location>/var/log/nginx/access.log</location>
</localfile>

<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/postgresql/postgresql-*.log</location>
</localfile>
```

### Group agent.conf (web-servers)
```xml
<agent_config>
  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/nginx/access.log</location>
  </localfile>
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/postgresql/postgresql-*.log</location>
  </localfile>
</agent_config>
```
