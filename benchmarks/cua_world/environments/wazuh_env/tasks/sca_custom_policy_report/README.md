# Task: sca_custom_policy_report

## Domain Context

**Primary users**: Compliance Engineers, GRC Analysts, Security Management Specialists
**GDP footprint**: $199M (security management / compliance category)
**Real workflow**: "Used for monitoring incident logs and converging physical/logical security data"

Security Configuration Assessment (SCA) and compliance gap analysis are core activities for GRC professionals. Creating custom policies for organization-specific requirements goes beyond default CIS benchmarks and reflects real regulatory compliance work.

## Task Overview

Review existing Wazuh SCA results, create a custom Wazuh SCA policy YAML file with >= 3 company-specific checks, configure Wazuh to run it, and produce a compliance gap analysis report.

## Goal / End State

1. A custom SCA policy YAML file exists in `/var/ossec/etc/shared/` with valid Wazuh SCA schema structure and >= 3 check entries
2. `ossec.conf` has been updated to reference this custom policy in the `<sca>` section
3. A compliance gap analysis report exists at `/home/ga/Desktop/compliance_report.txt` with >= 500 characters documenting the findings

## Difficulty: very_hard

The agent must figure out:
- How to navigate to and interpret SCA results in the Wazuh dashboard
- The exact Wazuh SCA policy YAML schema (policy metadata, requirements, checks with rules)
- How to upload the YAML policy to Wazuh (via API: PUT /manager/files?path=etc/shared/custom_policy.yml, or via dashboard file manager)
- How to modify ossec.conf's `<sca>` section to reference the new policy file
- What compliance gap analysis should include (current posture, custom checks, remediation steps)

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| Custom SCA policy YAML in /var/ossec/etc/shared/ | 25 | Walk shared dirs, check for non-CIS YAML files with 'policy:' and 'checks:' |
| Policy has >= 3 check entries | 20 | Count '- id:' occurrences in YAML file |
| ossec.conf references custom (non-CIS) policy | 20 | Parse ossec.conf <sca> section for non-default policy paths |
| Compliance report at Desktop/compliance_report.txt | 20 | File existence check |
| Report >= 500 characters | 15 | wc -c on report file |

**Pass threshold**: 65 points
**Score cap**: Report is a required deliverable — score capped at 64 if missing

## Wazuh SCA Policy YAML Schema

```yaml
policy:
  id: "custom_org_policy_001"
  file: "custom_org_policy.yml"
  name: "Organization Custom Security Policy v1.0"
  description: "Custom security baseline checks for regulatory compliance"
  references:
    - https://www.cisecurity.org/

requirements:
  title: "Security Baseline Requirements"
  description: "Minimum security configuration for all servers"
  condition: any
  rules:
    - 'c:id -P'

variables:
  $sshd_config: /etc/ssh/sshd_config

checks:
  - id: 1001
    title: "Ensure SSH root login is disabled"
    description: "PermitRootLogin must be set to no"
    rationale: "Root SSH access bypasses sudo audit trail"
    remediation: "Set PermitRootLogin no in /etc/ssh/sshd_config and restart sshd"
    condition: all
    rules:
      - 'f:/etc/ssh/sshd_config -> r:^\s*PermitRootLogin\s+no'

  - id: 1002
    title: "Ensure SSH password authentication is disabled"
    description: "SSH key-only authentication must be enforced"
    rationale: "Password authentication is vulnerable to brute force"
    remediation: "Set PasswordAuthentication no in /etc/ssh/sshd_config"
    condition: all
    rules:
      - 'f:/etc/ssh/sshd_config -> r:^\s*PasswordAuthentication\s+no'

  - id: 1003
    title: "Ensure auditd service is running"
    description: "The audit daemon must be active for security event logging"
    rationale: "auditd captures security-relevant kernel events for forensic analysis"
    remediation: "Run: systemctl enable auditd && systemctl start auditd"
    condition: all
    rules:
      - 'p:auditd'
```

## Updating ossec.conf SCA Section

```xml
<sca>
  <enabled>yes</enabled>
  <scan_on_start>yes</scan_on_start>
  <interval>12h</interval>
  <skip_nfs>yes</skip_nfs>
  <policies>
    <policy>etc/shared/cis_ubuntu22-04.yml</policy>
    <policy>etc/shared/custom_org_policy.yml</policy>
  </policies>
</sca>
```

## Uploading via Wazuh API

```bash
curl -sk -X PUT "https://localhost:55000/manager/files?path=etc/shared/custom_policy.yml" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @custom_policy.yml
```

## Edge Cases

- The policy file path in ossec.conf should be relative to `/var/ossec/`: `etc/shared/custom_policy.yml`
- The Wazuh manager may need to be restarted for the new SCA policy to take effect
- The `checks` section must use proper YAML indentation — tab/space mixing causes parse errors
- SCA rule syntax uses Wazuh-specific commands: `f:` (file check), `p:` (process check), `c:` (command output), `d:` (directory check)
