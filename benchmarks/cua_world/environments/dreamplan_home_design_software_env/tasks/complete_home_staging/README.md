# Task: complete_home_staging

## Domain Context
Home staging is a real estate technique where interior designers furnish and arrange rooms to maximize a property's appeal to buyers. Professional stagers must place contextually appropriate furniture in each room and capture marketing-quality images for listings.

## Role
Professional Home Stager / Real Estate Staging Consultant

## Scenario
A real estate agent needs staged photography of the Contemporary House's three primary living spaces. The agent must furnish all three rooms with appropriate furniture and export separate 3D view images of each furnished room.

## What the Agent Must Do
1. Place at least a sofa AND a coffee table in the living room
2. Place a dining table AND at least two chairs in the dining room
3. Place a bed AND at least one additional item in a bedroom
4. Navigate to the living room in 3D view and export → `C:\Users\Docker\Desktop\staged_living_room.jpg`
5. Navigate to the dining room in 3D view and export → `C:\Users\Docker\Desktop\staged_dining_room.jpg`
6. Navigate to the bedroom in 3D view and export → `C:\Users\Docker\Desktop\staged_bedroom.jpg`

## Why This Is Hard
- Must browse DreamPlan's furniture catalog and find appropriate items for 3 distinct rooms
- Each room requires multiple furniture pieces (not just one item)
- Must navigate to each room and export 3 separate images with distinct filenames
- Total of 6+ furniture placement operations + 3 export operations across different rooms

## Verification Strategy
- `staged_living_room.jpg`: exists + is new + size > 30 KB (15+5+10 pts = 30 pts)
- `staged_dining_room.jpg`: exists + is new + size > 30 KB (15+5+10 pts = 30 pts)
- `staged_bedroom.jpg`: exists + is new + size > 30 KB (15+5+10 pts = 30 pts)
- All 3 files present: 10 pts bonus
- Total: 100 pts, pass threshold: 60 pts

## Environment
- DreamPlan already running with Contemporary House project loaded
- Windows 11, user: Docker
- No login credentials needed
