# Task: sprint_health_audit

## Overview

**Difficulty**: very_hard
**Occupation**: IT Project Manager / Scrum Master
**Domain**: Agile Sprint Planning and Capacity Management
**Azure DevOps Feature Areas**: Boards > Sprints (Capacity tab), Work Items, Iteration Path management

## Domain Context

IT Project Managers and Scrum Masters use Azure DevOps to manage sprint health: ensuring the team doesn't take on more work than it can complete (over-commitment), and that capacity planning reflects realistic throughput. A common real-world scenario is discovering that a sprint has been loaded with too many story points—requiring triage to defer lower-priority items and configure explicit capacity so the team knows its limits.

## Scenario

Sprint 1 of the TailwindTraders project is significantly over-committed. Five work items have been loaded into Sprint 1 with a combined 37 story points, but no team capacity has been configured. The project manager must:

1. Set team member capacity in the Sprint 1 capacity settings
2. Identify which Sprint 1 items can be deferred based on priority
3. Move at least two lower-priority items to Sprint 2
4. Document each triage decision with a comment

## What the Agent Must Discover

- Sprint 1 has ~37 story points spread across 5 work items
- No team capacity is configured (capacity tab shows zeros)
- Items range in priority: Priority 1 (critical bugs and high-value stories) vs Priority 2 (lower-value bugs and maintenance tasks)
- The agent must decide WHICH items to defer based on priority — not told which ones
- The agent must navigate to the correct UI (Sprints view, Capacity tab, individual work items)

## Pre-Task State (set by setup_task.ps1)

Story points assigned to Sprint 1 work items:
- "Implement product inventory search" (User Story, Priority 1): **13 story points**
- "Design REST API rate limiting" (User Story, Priority 1): **8 story points**
- "Product price calculation bug" (Bug, Priority 1): **5 story points**
- "API 500 error on special chars" (Bug, Priority 1): **3 story points**
- "Inventory count goes negative" (Bug, Priority 1): **8 story points**

Total Sprint 1 story points: **37**
Expected realistic velocity for a small team per sprint: **~20 story points**

## Success Criteria

| Criterion | Points | Verification Method |
|-----------|--------|---------------------|
| Team capacity set (≥1 team member, ≥1 hrs/day) | 20 | REST API: `/work/teamsettings/iterations/{id}/capacities` |
| At least 2 work items moved out of Sprint 1 | 40 | WIQL query: count Sprint 1 items vs baseline |
| Sprint 1 story points reduced by ≥35% | 20 | WIQL: sum StoryPoints where IterationPath=Sprint 1 |
| At least 1 moved item has a comment | 20 | Work item comments API |

**Pass threshold**: 60 / 100

## Verification Strategy

The `export_result.ps1` script:
1. Queries all Sprint 1 work items via WIQL
2. Sums their story points
3. Counts team member capacities via the capacities API
4. Checks comments on all project work items
5. Writes result to `C:\Users\Docker\task_results\sprint_health_audit_result.json`

The `verifier.py` compares against baseline to detect changes.

## Edge Cases

- Agent might set capacity in Sprint 2 instead of Sprint 1 (verifier checks Sprint 1 specifically)
- Agent might move items to Sprint 3 or Backlog (also valid, verifier checks "not Sprint 1")
- Sprint 1 story points after triage should be ≤ 24 (35% reduction from 37)
- Comments may be in any format (verifier just checks non-empty, non-whitespace)
