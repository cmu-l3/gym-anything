# Task: bcp_ransomware_response

## Domain Context

Business Continuity Planners at financial services firms are among the heaviest users of Wondershare EdrawMax for producing process documentation. A key deliverable in any incident response program is a visual cross-functional flowchart that maps team responsibilities during a security event. Ransomware is the highest-probability, highest-impact threat category for financial institutions, making this a high-priority recurring document type.

## Occupation

**Business Continuity Planners** (top EdrawMax user group by economic impact)

## Task Overview

Create a professional Ransomware Incident Response (IR) cross-functional swimlane diagram in EdrawMax and save it as a 2-page EDDX file.

## Goal / End State

The completed file `/home/ga/ransomware_ir_flowchart.eddx` must contain:

- **Page 1**: A cross-functional swimlane (pool) flowchart mapping the ransomware IR workflow from detection through post-incident review. Must include at least 3 team lanes (IT Security, Executive Management, Legal/Compliance), decision diamond shapes for branching logic (e.g., "Containment successful?", "RTO met?"), rectangular action steps, and directional connectors showing handoffs between lanes.
- **Page 2**: An Executive Summary or Incident Impact Assessment page with written text covering incident scope, affected systems, recovery time objective (RTO), and key lessons learned.
- A professional color theme applied to the diagram.

## Difficulty

**very_hard** — The task description provides the professional goal and required structural features but does NOT specify which EdrawMax menus, shape libraries, or dialog boxes to use. The agent must know (1) how to create a cross-functional flowchart using EdrawMax's swimlane diagram type, (2) which shape library contains decision diamonds for flowcharts, (3) how to add and name pages, and (4) how to apply themes — all without UI navigation hints.

## Success Criteria

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| A: Valid EDDX archive | 15 | File exists at correct path, is a valid ZIP |
| B: Modified after task start | 10 | File mtime > task start timestamp (anti-gaming) |
| C: Multi-page (≥ 2 pages) | 20 | Archive contains ≥ 2 page XML files |
| D: Swimlane structure | 15 | NameU attributes contain swim/lane/pool keywords |
| E: Shape density | 20 | ≥ 10 Shape elements AND ≥ 5 ConnectLine elements |
| F: Decision diamonds | 10 | NameU contains "decision" (case-insensitive) |
| G: Page 2 text content | 10 | ≥ 5 Chars elements on page 2 |

**Pass threshold: 60/100**

## Verification Strategy

The verifier (`verifier.py::verify_bcp_ransomware_response`) copies the EDDX file and a task-start timestamp from the VM, parses the EDDX as a ZIP archive, reads all XML files, and checks the criteria above using regex on raw XML content. No export_result.sh is needed — the EDDX format (ZIP+XML) is directly parseable.

## Anti-Gaming

- `setup_task.sh` deletes `/home/ga/ransomware_ir_flowchart.eddx` before launching EdrawMax
- `setup_task.sh` records `date +%s` to `/tmp/bcp_ransomware_response_start_ts` AFTER file deletion
- Verifier checks `file mtime > start_ts` so pre-existing stale files cannot pass

## Edge Cases

- Agent may use generic rectangle shapes instead of swimlane pools — verifier checks NameU for swim/lane/pool keywords. If the agent uses only generic shapes without swimlane structure, criterion D fails (15 pts lost).
- Agent may save to a different path — verifier only checks `/home/ga/ransomware_ir_flowchart.eddx`.
- Agent may forget Page 2 — criterion C (20 pts) and G (10 pts) both fail.

## Feature Matrix (this task vs. others in the environment)

| Feature | This task | sysarch | telecom | analyst | indusengg |
|---------|-----------|---------|---------|---------|-----------|
| Swimlane layout | ✓ | | | | |
| AWS/Cloud shapes | | ✓ | | | |
| Network shapes | | | ✓ | | |
| UML shapes | | | | ✓ | |
| VSM shapes | | | | | ✓ |
| Multi-page | ✓ | ✓ | ✓ | ✓ | ✓ |
| Decision diamonds | ✓ | | | | |
| Professional theme | ✓ | ✓ | ✓ | ✓ | ✓ |
