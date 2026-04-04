# security_incident_reopening

**Difficulty**: very_hard
**Environment**: redmine_env
**Occupation context**: DevOps Engineer / Security Engineer (Architecture and Engineering)

## Scenario

A DevOps/security engineer at DevLabs must handle a security incident: an SSL certificate issue previously marked "Resolved" had incomplete remediation. The certbot auto-renewal cronjob was never verified after a permission fix, and the certificate is again at risk.

The engineer must:
1. Reopen the SSL cert issue, escalate priority to Immediate, add a "REOPENED" comment
2. Create a new Bug tracking the monitoring gap (certbot cronjob failures not alerted)
3. Add a cross-reference comment on the original issue pointing to the new issue
4. Log 2.0h of Development time on the original issue

## Why This Is Very Hard

- Agent must find a **Resolved** issue (not visible on the default open-issues view)
- Requires navigating to a specific project, filtering by status, then reopening
- Creating a new issue with specific fields (category, version, estimated hours) requires multiple form interactions
- Agent must cross-reference a newly created issue by number (requires noting the ID)
- Time logging requires navigating to a separate "Log Time" form
- No step-by-step UI guidance provided

## Verification

`export_result.sh` fetches:
- Original SSL cert issue: status, priority, comments, time entries
- New certbot monitoring issue: subject, assigned_to, priority, version

`verifier.py` checks (20 pts each):
1. SSL cert status = In Progress
2. SSL cert priority = Immediate
3. SSL cert has comment containing "REOPENED"
4. New certbot issue exists, assigned to carol.santos, priority High, version Q1 2025 Goals
5. SSL cert has ≥2.0h Development time logged

Pass threshold: 60/100

## Seeded Data Used

- Project: `infra-devops`
- Issue: "SSL certificate for api.devlabs.io expires in 14 days" (Resolved, Urgent)
- Version: "Q1 2025 Goals"
- Users: carol.santos, admin
