# Defense Sector Visitor Host Compliance Audit

## Task Overview

ACME Corp's security policy mandates that all visitors from defense and aerospace companies
must be hosted exclusively by the Security department. Any visitor from a defense/aerospace
company who was hosted by a non-Security department represents a policy gap that requires
immediate documentation and escalation to the Security Director.

## Your Mission

You are the Compliance Officer at ACME Corp. Review the visitor records to identify all
visitors from defense and aerospace companies who were NOT hosted by the Security department.
This is a compliance gap — these visitors received access without proper Security oversight.
Export a compliance gap report.

## Goal State

A file named `defense_host_compliance.csv` must exist at `/home/ga/Desktop/` identifying
each defense/aerospace visitor who was hosted by a non-Security department. The report
should include visitor name, company name, host name, and host department for each violation.

## Credentials

- Application: Jolly LobbyTrack (already open)
- No username/password required

## What the Agent Must Discover

The agent must:
1. Know (from domain knowledge) which companies in the visitor records are classified
   as defense/aerospace companies (e.g., Boeing, Lockheed Martin, Raytheon Technologies,
   Northrop Grumman, General Dynamics)
2. Search or filter visitor records to find entries for these companies
3. Check the host department for each defense company visitor
4. Identify visitors whose host department is NOT "Security"
5. Export a compliance gap report to the specified path

## Success Criteria

The output file `/home/ga/Desktop/defense_host_compliance.csv` must:
- Exist at the specified path
- Identify Boeing Company and the non-Security host department
- Identify Lockheed Martin and the non-Security host department
- Identify Northrop Grumman and the non-Security host department
- Include host department information showing the compliance gap

## Verification Strategy

1. File existence — prerequisite; score=0 if missing
2. Boeing Company visit with non-Security host identified — 25 pts
3. Lockheed Martin visit with non-Security host identified — 25 pts
4. Northrop Grumman visit with non-Security host identified — 25 pts
5. Non-Security host departments referenced (Compliance, Legal, or Procurement) — 25 pts

Passing threshold: 70 points

## Schema Reference

Each visitor record includes: Company, Host First Name, Host Last Name, Host Department.
Defense/aerospace companies in the dataset: Boeing Company, Lockheed Martin, Raytheon
Technologies, Northrop Grumman, General Dynamics.
Security department host: Cynthia Parker (Security Director, ext-5333, Room 100).
