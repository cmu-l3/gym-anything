# Task: exterior_landscape_design

## Domain Context
Landscape architects design the exterior grounds of residential properties, including plantings, circulation paths, outdoor living structures, and exterior building finishes. A complete landscape design package includes both a site plan (overhead) and a rendered 3D view.

## Role
Landscape Architect

## Scenario
The Contemporary House needs a full exterior and landscape design. The client wants mature plantings, a driveway or entry path, an outdoor living area, and a refreshed exterior wall finish. The deliverable includes a site plan, a 3D perspective, and a saved project.

## What the Agent Must Do
1. Add at least four trees or large shrubs distributed around the property
2. Add a driveway or primary walkway/path leading to the house entrance
3. Add an outdoor living structure (deck, patio, terrace, or pergola) adjacent to the house
4. Update the exterior wall material or paint color of the house
5. Export overhead/top-down site plan → `C:\Users\Docker\Desktop\landscape_site_plan.jpg`
6. Export 3D exterior perspective → `C:\Users\Docker\Desktop\landscape_3d_view.jpg`
7. Save project → `C:\Users\Docker\Documents\landscape_design.dpn`

## Why This Is Hard
- Requires navigating DreamPlan's landscape/terrain/exterior tools (separate from interior tools)
- Must add four distinct landscaping elements in different locations
- Requires adding outdoor structures (deck/patio — a different tool category)
- Must change exterior wall material (distinct from interior material changes)
- Requires switching to an overhead/aerial view for the site plan export

## Verification Strategy
- `landscape_site_plan.jpg`: exists + is new + size > 15 KB (25+10+10 pts = 45 pts)
- `landscape_3d_view.jpg`: exists + is new + size > 30 KB (25+10+10 pts = 45 pts)
- `landscape_design.dpn`: exists + is new (7+3 pts = 10 pts)
- Total: 100 pts, pass threshold: 60 pts

## Environment
- DreamPlan already running with Contemporary House project loaded
- Windows 11, user: Docker
- No login credentials needed
