# Create Sprint Review Dashboard (`create_sprint_dashboard@1`)

## Overview

This task evaluates the agent's ability to create and configure a project dashboard in Azure DevOps Server with multiple widget types. The agent must build a "Sprint 1 Review" dashboard for stakeholders that includes query-driven tiles, a burndown chart, a work item distribution chart, and formatted markdown notes—all connected to real project data.

## Rationale

**Why this task is valuable:**
- Tests navigation of a complex, multi-panel configuration UI (dashboard editor, widget catalog, widget settings dialogs)
- Requires connecting widgets to backend data sources (shared queries, iteration paths)
- Evaluates understanding of Azure DevOps information architecture
- Involves both creative composition (layout) and precise configuration (query binding, iteration selection)

**Real-world Context:** A Scrum Master needs to create a single dashboard view for an executive sprint review meeting to summarize sprint health (bugs, work distribution, goals) without navigating through multiple backlog pages.

## Task Description

**Goal:** Create a new project dashboard named **"Sprint 1 Review"** in the TailwindTraders project and populate it with at least four configured widgets.

**Starting State:**
- Azure DevOps Server is open to the TailwindTraders project.
- Shared queries "Active Bugs" and "Sprint 1 All Items" exist.
- No dashboard named "Sprint 1 Review" exists.

**Expected Actions:**
1. Navigate to **Overview > Dashboards**.
2. Create a new dashboard named **"Sprint 1 Review"**.
3. Add and configure a **Markdown** widget with the specified Sprint Goals text.
4. Add and configure a **Query Tile** widget linked to the **"Active Bugs"** query.
5. Add and configure a **Chart for Work Items** widget linked to **"Sprint 1 All Items"**, grouped by **State**.
6. Add at least one other widget of choice.
7. Save the dashboard.

**Final State:**
- Dashboard "Sprint 1 Review" exists with >= 4 functional widgets showing real data.

## Verification Strategy

### Primary Verification: API State Check
The verifier queries the Azure DevOps REST API to:
1. Confirm the dashboard exists.
2. Enumerate widgets and verify count >= 4.
3. Parse widget settings to verify correct query bindings and markdown content.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Dashboard Created | 15 | Dashboard named "Sprint 1 Review" exists |
| Widget Count | 15 | At least 4 widgets present |
| Markdown Content | 20 | Contains required sprint goals text |
| Query Tile Config | 20 | Bound to "Active Bugs" query |
| Chart Config | 20 | Bound to "Sprint 1 All Items" and Group By State |
| Extra Widget | 10 | Fourth widget of any type present |
| **Total** | **100** | |

Pass Threshold: 60 points