# Task: PCI DSS Compliance Controls

## Overview

**Difficulty**: Very Hard
**Timeout**: 600 seconds | **Max Steps**: 85
**Primary Occupation**: GRC/Compliance Engineer / Security Engineer

This task simulates a real compliance engineering workflow where a financial services company must implement PCI DSS Requirement 10 audit log monitoring controls in Wazuh before an upcoming QSA assessment.

## Domain Context

**PCI DSS Requirement 10** mandates: "Track and monitor all access to network resources and cardholder data." Key sub-requirements include:

| Sub-req | Control |
|---------|---------|
| 10.1 | Implement audit trails for all system components |
| 10.2 | Implement audit log events for individual access to cardholder data |
| 10.2.4 | Invalid logical access attempts |
| 10.2.5 | Use of and changes to identification/authentication mechanisms |
| 10.2.7 | Creation and deletion of system-level objects |
| 10.3 | Record at minimum: user identification, type of event, date/time, success/fail |
| 10.5 | Secure audit trails so they cannot be altered |
| 10.6 | Review logs and security events for all system components |
| 10.7 | Retain audit log history for at least one year |

## Starting State

- No PCI DSS-specific SCA policy exists
- Email alerting is not configured in ossec.conf
- No PCI DSS-specific detection rules in local_rules.xml
- No compliance report document exists

## Goal (End State)

1. **Custom SCA policy YAML** with ≥5 checks targeting PCI DSS Req 10 controls, deployed to `/var/ossec/etc/shared/`
2. **Email alerting** configured in ossec.conf (`smtp_server`, `email_from`, `email_to`)
3. **≥2 detection rules** (level ≥10) for PCI DSS Req 10 violations (unauthorized access, log tampering, auth failures)
4. **Compliance evidence report** at `/home/ga/Desktop/pci_compliance_report.txt` (≥800 chars) mapping controls to sub-requirements

## Scoring (100 points total)

| Criterion | Points |
|-----------|--------|
| PCI DSS SCA policy with ≥5 compliance checks | 25 |
| Email alerting (smtp + from + to) in ossec.conf | 20 |
| ≥2 detection rules covering distinct PCI violations (level ≥10) | 25 |
| Compliance report ≥800 chars with PCI DSS content, created after task start | 20 |
| ossec.conf meaningfully updated | 10 |

**Pass threshold**: 65 points
**Score cap**: If report missing and score ≥65, cap at 64

## Key Wazuh Concepts

### SCA Policy YAML Structure
```yaml
policy:
  id: "pci_dss_req10"
  file: "pci_dss_req10.yaml"
  name: "PCI DSS Requirement 10 - Audit Log Monitoring"
  description: "Checks for PCI DSS Requirement 10 compliance controls"
  references:
    - https://www.pcisecuritystandards.org/

requirements:
  title: "PCI DSS v3.2.1 Requirement 10"
  description: "Track and Monitor All Access to Network Resources"
  condition: all
  rules:
    - 'c:auditctl -l -> r:auditctl|no rules'

variables:
  $audit_conf: /etc/audit/audit.rules,/etc/audit/rules.d
  $log_dir: /var/log

checks:
  - id: 10001
    title: "Ensure auditd service is running (PCI DSS 10.1)"
    description: "The auditd service must be active to capture audit events"
    rationale: "PCI DSS 10.1 requires audit trails for all system components"
    remediation: "Run: systemctl enable auditd && systemctl start auditd"
    compliance:
      - pci_dss: "10.1"
    condition: all
    rules:
      - 'c:systemctl is-active auditd -> r:^active'
```

### Email Alerting in ossec.conf
```xml
<global>
  <email_notification>yes</email_notification>
  <smtp_server>smtp.company.com</smtp_server>
  <email_from>wazuh@company.com</email_from>
  <email_to>security@company.com</email_to>
  <email_maxperhour>12</email_maxperhour>
  <email_alert_level>12</email_alert_level>
</global>
```

### PCI DSS Detection Rules
```xml
<rule id="100070" level="12">
  <if_sid>5101</if_sid>
  <match>root</match>
  <description>PCI DSS 10.2.2: Root privileged access to system (Req 10.2.2)</description>
  <group>pci_dss_10.2.2,audit,authentication</group>
</rule>

<rule id="100071" level="14">
  <if_sid>591</if_sid>
  <match>auth.log|syslog</match>
  <description>PCI DSS 10.5: Possible audit log tampering detected (Req 10.5)</description>
  <group>pci_dss_10.5,audit_integrity</group>
</rule>
```

## Files Modified

- `/var/ossec/etc/shared/<policy_name>.yaml` — PCI DSS SCA policy
- `/var/ossec/etc/ossec.conf` — Email alerting configuration
- `/var/ossec/etc/rules/local_rules.xml` — PCI DSS detection rules
- `/home/ga/Desktop/pci_compliance_report.txt` — Compliance evidence report
