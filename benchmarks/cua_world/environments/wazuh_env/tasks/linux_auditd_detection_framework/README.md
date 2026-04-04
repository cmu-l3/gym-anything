# Task: Linux Auditd Detection Framework

## Overview

**Difficulty**: Very Hard
**Timeout**: 600 seconds | **Max Steps**: 80
**Primary Occupation**: Information Security Engineer / Detection Engineer

This task simulates a realistic detection engineering scenario where the Linux audit subsystem's event logs are flowing into Wazuh but currently have no decoder pipeline — all privilege escalation attempts, credential file accesses, and suspicious syscalls pass through undetected.

## Domain Context

Linux `auditd` is the kernel-level audit framework that records security-relevant events. Real-world SOC teams use Wazuh to process auditd events and alert on:

- **T1548.003** – Abuse Elevation Control (sudo, SUID binaries, pkexec)
- **T1003.008** – OS Credential Dumping (/etc/shadow access)
- **T1059.004** – Command and Scripting Interpreter: Unix Shell

The challenge: `auditd` logs have a complex multi-record format (`type=SYSCALL`, `type=EXECVE`, `type=PATH` linked by audit message IDs) that requires a careful parent-child decoder chain.

## Starting State

- `/var/log/audit/audit.log` contains real-format audit events showing privilege escalation and credential access
- `local_decoder.xml` has only the baseline GymApp decoder — no audit decoder
- `local_rules.xml` has only the baseline 3 rules — no auditd rules
- `/var/ossec/etc/lists/` contains no executable path CDB list
- `ossec.conf` does not monitor `/var/log/audit/audit.log`

## Goal (End State)

1. **Auditd decoder chain**: parent decoder matching audit log format, child decoder extracting fields
2. **≥2 detection rules** covering distinct threat categories (privilege escalation, credential access, suspicious execution)
3. **≥1 rule with MITRE ATT&CK mapping** (`<mitre><id>T1548</id></mitre>` style)
4. **CDB list** with ≥3 high-risk executable paths (e.g., `/usr/bin/sudo`, `/usr/bin/pkexec`, `/bin/su`)
5. **ossec.conf** updated to monitor `/var/log/audit/audit.log`

## Scoring (100 points total)

| Criterion | Points |
|-----------|--------|
| Auditd parent + child decoder chain | 20 |
| ≥2 detection rules, ≥2 distinct threat categories | 25 |
| ≥1 rule with MITRE ATT&CK technique mapping | 15 |
| CDB list with ≥3 high-risk executable paths | 20 |
| ossec.conf monitoring /var/log/audit/audit.log | 20 |

**Pass threshold**: 60 points

## Key Wazuh Concepts

### Audit Log Format (real Linux kernel format)
```
type=SYSCALL msg=audit(1706823600.123:1001): arch=c000003e syscall=59 success=yes ... comm="sudo" exe="/usr/bin/sudo" key="privilege_escalation"
type=EXECVE msg=audit(1706823600.123:1001): argc=3 a0="sudo" a1="-s" a2="/bin/bash"
type=PATH msg=audit(1706823600.123:1001): item=0 name="/etc/shadow" ...
```

### Parent Decoder
```xml
<decoder name="auditd">
  <prematch>type=\w+ msg=audit(</prematch>
</decoder>
```

### Child Decoder
```xml
<decoder name="auditd-execve">
  <parent>auditd</parent>
  <prematch>type=EXECVE </prematch>
  <regex>argc=(\d+) a0="(\S+)"</regex>
  <order>argc,command</order>
</decoder>
```

### Detection Rule with MITRE
```xml
<rule id="100060" level="12">
  <decoded_as>auditd</decoded_as>
  <field name="key">privilege_escalation</field>
  <description>Linux privilege escalation via sudo detected (T1548)</description>
  <mitre><id>T1548.003</id></mitre>
  <group>audit,privilege_escalation</group>
</rule>
```

### CDB List Format (in /var/ossec/etc/lists/high-risk-binaries)
```
/usr/bin/sudo:
/usr/bin/pkexec:
/bin/su:
/usr/bin/newgrp:
/usr/bin/passwd:
```

### ossec.conf: Monitor audit.log
```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/audit/audit.log</location>
</localfile>
```

## Files Modified

- `/var/ossec/etc/decoders/local_decoder.xml` — Add auditd parent + child decoders
- `/var/ossec/etc/rules/local_rules.xml` — Add privilege escalation and credential access rules
- `/var/ossec/etc/lists/high-risk-binaries` (or similar) — CDB list
- `/var/ossec/etc/ossec.conf` — Add localfile entry for audit.log
