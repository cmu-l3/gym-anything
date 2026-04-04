# Task: construction_document_set

## Domain Context
General contractors and architects prepare construction document sets before breaking ground on a renovation. A standard set includes elevation drawings (front and side views), a dimensioned floor plan, and a 3D overview. These views communicate different aspects of the design to different trades.

## Role
General Contractor (preparing documentation for client review and subcontractor use)

## Scenario
The Contemporary House renovation is approved and the contractor must produce a four-view documentation package: two elevation drawings, a 2D floor plan, and a 3D overview. All four must be separate files. The project must also be saved for future revisions.

## What the Agent Must Do
1. Export front elevation view → `C:\Users\Docker\Desktop\elevation_front.jpg`
2. Export side elevation view (left or right) → `C:\Users\Docker\Desktop\elevation_side.jpg`
3. Export 2D ground floor plan → `C:\Users\Docker\Desktop\construction_floor_plan.jpg`
4. Export 3D overview perspective → `C:\Users\Docker\Desktop\construction_overview.jpg`
5. Save project → `C:\Users\Docker\Documents\construction_docs.dpn`

## Why This Is Hard (very_hard)
- Elevation views (front, side) require switching to elevation view mode — not the default 3D or 2D mode
- Must produce FOUR different exports from FOUR different view modes/positions
- Each file requires a distinct view setup before exporting
- Discovering the elevation view mode requires exploring DreamPlan's view controls
- Agent must name each file precisely to match the required filenames

## Verification Strategy
- `elevation_front.jpg`: exists + is new + size > 10 KB (10+5+5 pts = 20 pts)
- `elevation_side.jpg`: exists + is new + size > 10 KB (10+5+5 pts = 20 pts)
- `construction_floor_plan.jpg`: exists + is new + size > 10 KB (10+5+5 pts = 20 pts)
- `construction_overview.jpg`: exists + is new + size > 10 KB (10+5+5 pts = 20 pts)
- `construction_docs.dpn`: exists + is new (15+5 pts = 20 pts)
- Total: 100 pts, pass threshold: 60 pts

## Environment
- DreamPlan already running with Contemporary House project loaded
- Windows 11, user: Docker
- No login credentials needed
