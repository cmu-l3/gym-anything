# Task: user_access_audit

## Overview

**Role**: Security Compliance Analyst / Information Security Engineer
**Difficulty**: very_hard
**Domain**: Compliance — User Access Audit with Lookup Tables

Compliance audits require structured, traceable user access data. A key Splunk skill is building lookup tables from SIEM data and using them to enrich subsequent searches. This task models the real workflow of creating a Splunk-based user access report for an external audit.

## Goal

1. Analyze the `security_logs` index to identify the top users by authentication event count
2. Create a CSV lookup file named **`privileged_users.csv`** in Splunk containing at least 5 users
3. Configure a Splunk lookup definition named **`privileged_users_lookup`** pointing to that file
4. Create a saved report named **`User_Access_Audit_Report`** whose search references the lookup

## What the End State Looks Like

- `privileged_users.csv` exists in Splunk's lookup store (search app lookups directory)
- The CSV has at least 5 data rows (not counting header)
- A lookup definition named `privileged_users_lookup` is configured in Splunk
- A new saved search named `User_Access_Audit_Report` exists
- The saved search query contains `lookup privileged_users_lookup` or `inputlookup privileged_users`

## Verification Strategy

| Criterion | Score | Description |
|-----------|-------|-------------|
| Lookup file exists | 20% | `privileged_users.csv` exists in Splunk lookups |
| Lookup has ≥5 rows | 20% | CSV contains at least 5 data rows |
| Lookup definition configured | 20% | `privileged_users_lookup` is defined in Splunk |
| Report created | 20% | Saved search `User_Access_Audit_Report` exists |
| Report uses lookup | 20% | Report search contains lookup reference |

Score ≥ 60% = passed.

## Key Data Available

The `security_logs` index contains real SSH auth data. User names appear in log lines:
- `"Failed password for root from ..."` → user=root
- `"Accepted password for admin from ..."` → user=admin

The agent needs to extract usernames and count events per user, then save as CSV lookup.

## Schema Reference

Lookup file REST endpoint:
```
GET https://localhost:8089/servicesNS/-/-/data/lookup-table-files?output_mode=json
```

Lookup definition REST endpoint:
```
GET https://localhost:8089/servicesNS/-/-/data/transforms/lookups?output_mode=json
```

Filesystem path for lookups (search app):
```
/opt/splunk/etc/apps/search/lookups/
```

Example SPL to create lookup data:
```spl
index=security_logs
| rex field=_raw "(?:for|user)\s+(?P<username>\w+)\s+from"
| stats count as event_count by username
| sort -event_count
| head 10
| outputlookup privileged_users.csv
```
