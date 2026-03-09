# Task: work_item_triage_and_query

## Overview

**Difficulty**: hard
**Occupation**: Computer Systems Analyst / IT Project Manager
**Domain**: Work Item Management, Backlog Analysis, Query Creation
**Azure DevOps Feature Areas**: Boards > Work Items, Boards > Queries (WIQL), Work Item editing (bulk)

## Domain Context

Computer Systems Analysts are the top GDP-contributing occupation for Azure DevOps Server. Their primary use is tracking requirements, bugs, and sprint tasks. A core real-world scenario is discovering that the bug backlog is poorly managed: critical bugs have no owners, are miscategorized, and there's no dashboard query for leadership. The analyst must triage, reassign, recategorize, and create a tracking query.

## Scenario

An audit of the TailwindTraders bug backlog reveals:
- All 3 Priority 1 bugs are unassigned (no team member responsible)
- Priority 1 bugs are filed under `TailwindTraders\Uncategorized` instead of `TailwindTraders\Backend API`
- No shared query exists for leadership to track the critical bug backlog

The analyst must fix the assignment, correct the routing, and create the tracking query.

## What the Agent Must Discover

- Navigate to Work Items and filter for Priority 1 bugs (not told which items are wrong)
- Discover that the items are unassigned and miscategorized
- Understand how to edit area paths in Azure DevOps
- Know how to create a WIQL query and save it as a shared team query
- Understand that tags can be added via work item edit

## Pre-Task State (set by setup_task.ps1)

- `TailwindTraders\Backend API` area path is created
- `TailwindTraders\Uncategorized` area path is created
- All 3 Priority 1 bugs are:
  - Set to `AssignedTo = ""` (unassigned)
  - Set to area path `TailwindTraders\Uncategorized`
  - Tagged with no special tags (clean state)
- Baseline state recorded

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|--------------|
| All P1 bugs now have an assignee | 30 | WIQL: P1 bugs where AssignedTo != "" |
| P1 bugs area path corrected to Backend API | 25 | WIQL: P1 bugs area path check |
| Shared query "Critical Bug Backlog" exists | 30 | REST: `/wit/queries/Shared Queries` recursive |
| P1 bugs tagged with 'needs-owner' | 15 | Work item Tags field check |

**Pass threshold**: 60 / 100

## Verification Strategy

`export_result.ps1`:
1. Queries all Priority 1 bugs with their current assignee, area path, and tags
2. Queries the shared queries folder for any query matching "Critical Bug Backlog"
3. Writes result JSON

## Notes

- The `Backend API` and `Uncategorized` area paths are created in setup
- If the area path `TailwindTraders\Backend API` doesn't appear in the UI initially, the agent may need to navigate to Project Settings to see it, or just type it directly in the work item area field
- The WIQL for the query should be: `SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Bug' AND [System.State] = 'Active' AND [Microsoft.VSTS.Common.Priority] = 1`
