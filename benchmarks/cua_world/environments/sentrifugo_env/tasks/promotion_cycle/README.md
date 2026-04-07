# promotion_cycle

**Difficulty**: very_hard
**Environment**: Sentrifugo v3.2 HRMS (Ubuntu GNOME, Docker MySQL 5.7)
**Domain**: HR talent management / promotion administration

## Overview

The VP of Human Resources has finalized Q1 2026 promotion decisions. The agent receives the promotion list on the Desktop (`~/Desktop/q1_2026_promotions.txt`). It must implement all promotions in Sentrifugo: first create the "Engineering Manager" job title (which does not exist in the system), then update four employees' job titles to reflect their new roles.

The task tests the agent's ability to understand sequencing (create title first, then assign), navigate between the Job Titles and Employee modules, and execute four distinct employee updates.

## Setup

The setup script deactivates any prior-run Engineering Manager title, resets all four employees' titles to their pre-promotion values (in case a prior run left them promoted), then drops the promotion document on the Desktop and navigates to the Job Titles page.

## Scoring (100 pts total, pass = 70)

| Criterion | Points |
|-----------|--------|
| "Engineering Manager" job title exists and is active | 20 |
| EMP001 James Anderson has "Engineering Manager" title | 20 |
| EMP006 Jessica Liu has "Senior Software Engineer" title | 20 |
| EMP012 Jennifer Martinez has "Senior Data Scientist" title | 20 |
| EMP019 Tyler Moore has "Sales Manager" title | 20 |

Scoring is binary per criterion (no partial credit). Pass threshold is 70 to ensure the agent must complete at least the title creation plus 2-3 promotions.

## Verification Strategy

The verifier queries `main_jobtitles` for the Engineering Manager title, then `main_users JOIN main_jobtitles` for each employee's current title. Uses `exec_in_env` for live MySQL queries against the `sentrifugo-db` container.

## Anti-Patterns Addressed

- **AP-4**: Binary scoring — no partial credit strategies can reach 70 pts without actual meaningful work.
- **AP-13**: All-or-nothing per criterion prevents threshold gaming.
