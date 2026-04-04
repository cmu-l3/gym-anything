# corporate_wellness_challenge

## Overview
An HR Manager at Apex Manufacturing sets up a 12-week corporate wellness challenge for 3 employees using the wger fitness management platform. This is a multi-step task that exercises user registration, workout routine creation, measurement category management, and nutrition plan creation.

## Occupation
**Human Resources Manager** (SOC 11-3121.00)
Industry: Business and Financial Operations

## Difficulty
**very_hard** — Requires reading a companion document, then performing multiple distinct operations across different sections of the wger application.

## Task Requirements

The agent must read a briefing document at `/home/ga/Documents/wellness_challenge_brief.txt` and then:

1. **Register 3 employee accounts** in the Default gym (gym ID 1):
   - `maria_chen` (Maria Chen, maria.chen@apexmfg.com)
   - `david_okonkwo` (David Okonkwo, david.okonkwo@apexmfg.com)
   - `sarah_patel` (Sarah Patel, sarah.patel@apexmfg.com)

2. **Create 3 personalized workout routines** (under admin account):
   - "Cardio Kickstart - Maria"
   - "Strength Foundations - David"
   - "Flexibility & Recovery - Sarah"

3. **Create measurement category** "BMI" with unit "index"

4. **Create nutrition plan** with description "Apex Wellness Q1 Team Plan"

## Scoring (100 points)

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 15 | maria_chen user with correct name/email |
| C2 | 15 | david_okonkwo user with correct name/email |
| C3 | 15 | sarah_patel user with correct name/email |
| C4 | 10 | "Cardio Kickstart - Maria" routine |
| C5 | 10 | "Strength Foundations - David" routine |
| C6 | 10 | "Flexibility & Recovery - Sarah" routine |
| C7 | 10 | "BMI" measurement category (unit: index) |
| C8 | 15 | "Apex Wellness Q1 Team Plan" nutrition plan |

**Pass threshold:** 70 points

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition and metadata |
| `setup_task.sh` | Pre-task setup: cleans state, writes companion document, records baselines |
| `export_result.sh` | Post-task: queries DB for created entities, writes result JSON |
| `verifier.py` | Multi-criterion programmatic verifier |
| `README.md` | This documentation |

## Key Design Decisions

- **Companion document pattern**: The task description directs the agent to read a briefing file rather than embedding all details directly. This tests the agent's ability to locate, read, and follow external instructions.
- **Identity gate**: If no users are created at all, score is 0 (prevents partial credit from unrelated entities).
- **Setup idempotency**: All target entities are deleted during setup to ensure clean state regardless of prior runs.
