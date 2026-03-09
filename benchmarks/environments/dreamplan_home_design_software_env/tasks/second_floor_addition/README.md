# Task: second_floor_addition

## Domain Context
Residential architects frequently design vertical additions to existing homes. A second-floor addition requires creating the upper structure, designing rooms, adding vertical circulation (stairs), and producing a full set of floor plan drawings for both levels plus an exterior view.

## Role
Residential Architect

## Scenario
The Contemporary House owners need more space. The architect must design a second floor above the existing footprint: at least two rooms, a staircase connecting both levels, and at least one window on the upper floor. The deliverable includes separate floor plans for each level and a 3D exterior.

## What the Agent Must Do
1. Add a second floor/story to the Contemporary House in DreamPlan
2. Create at least two rooms on the second floor
3. Add a staircase connecting ground floor to second floor
4. Add at least one window on the second floor
5. Export ground floor plan (2D) → `C:\Users\Docker\Desktop\ground_floor_plan.jpg`
6. Export second floor plan (2D) → `C:\Users\Docker\Desktop\second_floor_plan.jpg`
7. Export 3D exterior showing full two-story structure → `C:\Users\Docker\Desktop\two_story_exterior.jpg`
8. Save project → `C:\Users\Docker\Documents\two_story_design.dpn`

## Why This Is Hard (very_hard)
- Adding a second floor is not obvious — agent must discover DreamPlan's multi-floor feature
- Creating rooms on a new floor requires understanding the floor context/level switching
- Adding stairs requires finding the staircase tool (not trivially located)
- Requires producing TWO different floor plan exports (switching floor context between them)
- Four distinct output files required

## Verification Strategy
- `ground_floor_plan.jpg`: exists + is new + size > 10 KB (20+5+5 pts = 30 pts)
- `second_floor_plan.jpg`: exists + is new + size > 10 KB (20+5+5 pts = 30 pts)
- `two_story_exterior.jpg`: exists + is new + size > 30 KB (15+5+5 pts = 25 pts)
- `two_story_design.dpn`: exists + is new (10+5 pts = 15 pts)
- Total: 100 pts, pass threshold: 60 pts

## Environment
- DreamPlan already running with Contemporary House project loaded
- Windows 11, user: Docker
- No login credentials needed
