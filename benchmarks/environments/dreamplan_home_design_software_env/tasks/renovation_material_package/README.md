# Task: renovation_material_package

## Domain Context
Interior designers use home design software to prepare renovation proposals for clients. A key deliverable is a material specifications package: updated floor materials, wall finishes, and exported views that communicate the redesign clearly to the homeowner and contractors.

## Role
Interior Designer

## Scenario
A homeowner wants differentiated flooring across the Contemporary House: hardwood in the living room and bedrooms, tile in the kitchen. At least one room should also receive a wall color or material update. The agent must make all material changes and then produce a deliverable package with a 3D view, a 2D floor plan, and a saved project file.

## What the Agent Must Do
1. Apply hardwood flooring to the living room
2. Apply ceramic/stone tile flooring to the kitchen
3. Apply hardwood flooring to at least one bedroom
4. Update wall color or wall material in at least one room
5. Export 3D view → `C:\Users\Docker\Desktop\renovation_3d_view.jpg`
6. Export 2D floor plan → `C:\Users\Docker\Desktop\renovation_floor_plan.jpg`
7. Save project → `C:\Users\Docker\Documents\renovation_proposal.dpn`

## Why This Is Hard
- Requires navigating DreamPlan's material/flooring system (multiple menus)
- Must correctly identify and select floor surfaces in specific rooms
- Requires switching view modes (3D vs 2D) to produce different exports
- Three distinct output files must each be created with correct names

## Verification Strategy
- `renovation_3d_view.jpg`: exists + is newer than task start + size > 30 KB (20+10+20 pts)
- `renovation_floor_plan.jpg`: exists + is newer than task start + size > 10 KB (15+10+10 pts)
- `renovation_proposal.dpn`: exists + is newer than task start (10+5 pts = 15 pts)
- Total: 100 pts, pass threshold: 60 pts

## Environment
- DreamPlan already running with Contemporary House project loaded
- Windows 11, user: Docker
- No login credentials needed
