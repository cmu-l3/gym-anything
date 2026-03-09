# milestone_replanning

**Difficulty**: very_hard
**Environment**: redmine_env
**Occupation context**: Project Manager / Engineering Manager (Computer and Mathematical)

## Scenario

A project manager at DevLabs must perform sprint replanning for the Infrastructure & DevOps project after a planning meeting. The centralized log aggregation work is being pulled forward from Q2 to Q1 2025, and the Kubernetes cluster setup is elevated to Immediate priority as the critical path for multiple workstreams.

## Actions Required

1. **Move log aggregation**: Change milestone from Q2 2025 Goals → Q1 2025 Goals; priority Normal → High
2. **Escalate K8s**: Change priority High → Immediate; add "REPRIORITIZED" comment about critical path
3. **Notify team**: Create a new Support issue for alice.chen announcing the scope change

## Why This Is Very Hard

- Agent must navigate Redmine's version/milestone editing flow
- Requires finding issues by description in a project issue list (not by numeric ID)
- Must change both the version (milestone) and priority fields simultaneously in an issue edit form
- Must create a new issue with specific fields across a different tracker (Support)
- No explicit step-by-step guidance — only high-level goal description

## Verification

`export_result.sh` fetches:
- Log aggregation issue: current version, current priority, baseline state
- K8s issue: current priority, comments, baseline state
- New scope change issue in infra-devops: subject, assigned_to

`verifier.py` checks (20 pts each):
1. Log aggregation version = Q1 2025 Goals
2. Log aggregation priority = High
3. K8s priority = Immediate
4. K8s has comment containing "REPRIORITIZED"
5. New scope change issue exists, assigned to alice.chen

Pass threshold: 60/100

## Seeded Data Used

- Project: `infra-devops`
- Issues: "Implement centralized log aggregation with OpenSearch" (Q2 2025 Goals, Normal), "Set up Kubernetes cluster for production workloads" (Q1 2025 Goals, High)
- Users: alice.chen, carol.santos
