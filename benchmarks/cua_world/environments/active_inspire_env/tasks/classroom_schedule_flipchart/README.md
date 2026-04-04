# Task: classroom_schedule_flipchart

## Overview

An elementary school teacher needs a daily classroom schedule display flipchart. This task requires creating a 2-page ActivInspire flipchart: a daily schedule page with at least 5 colored rectangle time blocks (each containing a time and activity), and a homework page with labeled subject boxes. This is one of the most common real-world uses of ActivInspire — teachers project a daily schedule board on the classroom screen throughout the day.

## Domain Context

Elementary teachers routinely use ActivInspire to create classroom display boards that remain visible throughout the day. A daily schedule board requires creating multiple colored rectangles arranged vertically to represent time blocks, with both time labels and activity names inside each block. This tests the agent's ability to create multiple shapes with distinct fill colors — a common but non-trivial ActivInspire workflow.

## Goal

Create a 2-page flipchart saved as `/home/ga/Documents/Flipcharts/daily_schedule.flipchart` with:

- **Page 1 — Daily Schedule**: Title "Daily Schedule" at top; at least 5 colored rectangle blocks containing the following schedule items with times: "8:00 - Morning Meeting", "9:00 - Reading", "10:00 - Math", "11:00 - Science", "12:00 - Lunch". Each rectangle should have a distinct fill color.
- **Page 2 — Homework**: Title "Homework" at top; at least 3 labeled rectangle boxes for Math, Reading, and one other subject, each containing a homework assignment description.

## Starting State

ActivInspire is running with a blank or default flipchart. No existing file named daily_schedule.flipchart in Documents/Flipcharts.

## Agent Workflow

The agent must:

1. Create a 2-page flipchart
2. On page 1: add title and create at least 5 colored rectangle blocks with time/activity labels
3. On page 2: add title and create labeled homework boxes for subjects
4. Apply different fill colors to the schedule blocks (requires using the fill/color tool)
5. Save to the specified path

This is the most shape-intensive task — it requires creating 8+ rectangles across two pages with different colors, which tests efficient use of the shape and color tools.

## Success Criteria (100 points total, pass at 70)

| Criterion | Points | Description |
|-----------|--------|-------------|
| File exists + valid format | 15 | File at expected path, valid flipchart ZIP/XML |
| Page count = 2 | 10 | Flipchart has exactly 2 pages |
| "Schedule" text present | 10 | "Schedule" found in XML |
| Schedule activities present | 20 | At least 3 of: "Morning Meeting", "Reading", "Math", "Science", "Lunch" |
| Rectangle shapes ≥ 8 | 20 | 8+ rectangles (5 schedule blocks + 3 homework boxes) |
| "Homework" text present | 15 | "Homework" found in XML |
| Subject homework items | 10 | At least 2 of "Math", "Reading", "Science", "Writing" in XML |

## Verification Approach

1. **File validation**: ZIP/XML format at exact path
2. **Page count**: Count page XML files in ZIP
3. **Text content**: Search all page XMLs for schedule activities and homework subjects
4. **Rectangle count**: Count AsRectangle elements across all page XMLs
5. **Timestamp**: File newer than task start time

## Anti-Gaming

- Rectangle count ≥ 8 enforces actual block creation (not just text)
- Multiple specific activity names required (not just "Schedule" title)
- Homework page separately verified
- 2-page requirement means agent must manage a second page
