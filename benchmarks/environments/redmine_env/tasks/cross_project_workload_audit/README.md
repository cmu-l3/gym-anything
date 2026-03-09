# cross_project_workload_audit

**Difficulty**: very_hard
**Environment**: redmine_env
**Occupation context**: Project Manager / Engineering Manager (Computer and Mathematical)

## Scenario

A project manager at DevLabs needs to perform a cross-project workload audit. Among four developers (bob.walker, carol.santos, david.kim, grace.lee), they must determine who is most overloaded by counting open issues (New/In Progress/Feedback) across all projects, then rebalance by reassigning the most-loaded developer's lowest-priority New-status issue.

Based on seeded data:
- carol.santos: 6 open issues (most loaded) — 4 in phoenix-ecommerce + 2 in infra-devops
- david.kim: 5 open issues
- bob.walker: 3 open issues (least loaded, tied with grace.lee)
- grace.lee: 3 open issues (least loaded, tied with bob.walker)

The target reassignment is carol.santos's only New-status issue: "Implement centralized log aggregation with OpenSearch" (Normal priority, infra-devops, estimated 60h) → reassign to bob.walker or grace.lee.

## Why This Is Very Hard

- Agent must browse across 3 projects to count each developer's open issues
- Requires multi-dimensional reasoning: find most-loaded dev, then find their lowest-priority New issue
- No specific issue is named — agent must discover it through browsing
- After reassignment: log 0.5h Design time, add comment, update estimated hours
- Requires understanding Redmine's filtered issue views and time logging forms

## Verification

`export_result.sh` fetches the log aggregation issue (expected target):
- Current assignee, estimated_hours, comments, time_entries

`verifier.py` checks (25 pts each):
1. Issue reassigned away from Carol Santos
2. New assignee is bob.walker or grace.lee
3. Issue has workload/rebalancing comment
4. ≥0.5h Design activity logged

Pass threshold: 50/100 (2+ criteria met)

## Seeded Data Used

- Project: `infra-devops`
- Issue: "Implement centralized log aggregation with OpenSearch" (New, Normal, carol.santos, 60h)
- All projects' issue lists used for workload counting
