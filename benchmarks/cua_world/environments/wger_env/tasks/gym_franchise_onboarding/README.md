# Task: gym_franchise_onboarding

## Overview
A fitness center manager is onboarding a new franchise location ("Iron Peak Fitness") and must set up the gym's digital infrastructure across four distinct wger modules. This is a **very_hard** difficulty task primarily because the agent must navigate across multiple application sections from a single starting point (the dashboard).

## Occupation
**Fitness Center Manager** (SOC 11-9051.00)
Industry: Personal Care and Service / Management

## What the Agent Must Do

### A. Staff and Member Registration (User Management Module)
Register 4 accounts under the Default gym (ID 1):
| Username | First | Last | Email |
|---|---|---|---|
| coach_rivera | Carlos | Rivera | carlos.rivera@ironpeakfit.com |
| coach_nakamura | Yuki | Nakamura | yuki.nakamura@ironpeakfit.com |
| front_desk_jones | Tamika | Jones | tamika.jones@ironpeakfit.com |
| member_williams | Derek | Williams | derek.williams@ironpeakfit.com |

### B. Starter Workout Routine (Routine Module)
- Create routine: "New Member Welcome Routine"
- Description: "Standard 4-week introductory program for all new Iron Peak Fitness members"
- Add 3 training days:
  - "Full Body Intro" (Monday)
  - "Upper Body Focus" (Wednesday)
  - "Lower Body & Core" (Friday)

### C. Nutrition Template (Nutrition Module)
- Create nutrition plan with description: "30-Day Transformation Kickstart"

### D. Body Composition Tracking (Measurement Module)
- Create category: "Body Fat Percentage" (unit: %)
- Create category: "Lean Muscle Mass" (unit: kg)

## Scoring (100 points)
| Criterion | Points | Description |
|---|---|---|
| C1-C4 | 10 each (40 total) | Each user exists with correct first/last/email |
| C5 | 10 | Routine exists with correct description |
| C6-C8 | 5 each (15 total) | Each training day exists |
| C9 | 5 | At least 2 days have correct day-of-week |
| C10 | 10 | Nutrition plan exists |
| C11-C12 | 10 each (20 total) | Each measurement category exists with correct unit |

**Pass threshold:** 65 points
**Gate:** If zero users exist AND routine doesn't exist, score = 0 (do-nothing protection)

## Difficulty Rationale
This task spans 4 distinct wger feature areas (user management, routines, nutrition, measurements), requiring the agent to navigate the full application from the dashboard. The primary difficulty axis is multi-module navigation (Lesson 142), not the complexity of any individual action.

## Files
- `task.json` — Task definition
- `setup_task.sh` — Pre-task cleanup and browser launch
- `export_result.sh` — Post-task data extraction
- `verifier.py` — Multi-criterion scoring verifier
