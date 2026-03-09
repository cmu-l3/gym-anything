# emergency_shelter_layout

**Occupation**: Urban/Regional Planner
**Industry**: Emergency Management / Government
**Difficulty**: Extremely Hard

## Task Description

Convert a large building into a disaster relief emergency shelter capable of housing 30 displaced families. The building shell is pre-drafted in Sweet Home 3D. The agent must use **4 distinct Sweet Home 3D features** to establish the shelter layout:

1. **Wall creation** -- build privacy partition walls to separate sleeping areas from other zones
2. **Door/window placement** -- install doors for zone separation and emergency egress between partitioned areas
3. **Label placement** -- place text labels to identify each functional zone for first responders
4. **Furniture placement** -- furnish five distinct zones for their emergency management functions

### Required Zones

- **Sleeping Dormitory** -- 30+ beds/cots for displaced individuals
- **Communal Dining / Supply Distribution** -- 6+ tables, 30+ chairs for meal service
- **Intake / Admin Command Post** -- 4+ desks for registration, case management, and coordination
- **Sanitation Facilities** -- 3+ toilets, 3+ sinks
- **Supply Storage** -- 6+ shelving/cabinet units for emergency provisions, blankets, and hygiene kits

## Features Used

| Feature | Used | Criterion |
|---------|------|-----------|
| Furniture catalog placement | Yes | C1, C3, C5 |
| Wall creation | Yes | C2 |
| Door/window placement | Yes | C2 |
| Label placement | Yes | C4 |

## Scoring

| Criterion | Points | Requirement | Partial Credit |
|-----------|--------|-------------|----------------|
| C1: Sleeping dormitory | 25 | >=30 beds/cots | >=20 -> 15 pts, >=10 -> 8 pts |
| C2: Partition walls + doors | 20 | >=3 new walls + >=2 doors | >=1 wall + >=1 door -> 10 pts |
| C3: Dining/distribution hall | 20 | >=6 tables + >=30 chairs | >=3 tables + >=15 chairs -> 10 pts |
| C4: Zone labels | 15 | >=3 labels or named rooms | >=1 -> 7 pts |
| C5: Admin + sanitation + storage | 20 | >=4 desks, >=3 toilets+sinks, >=6 shelves, file saved | Sub-scored: 5 pts each |
| **Total** | **100** | **Pass: 70** | |

Wrong-target gate: <10 furniture items = score 0.

## Starter File

Stripped from `SweetHome3DExample7.sh3d` (contemporary villa). All furniture removed; walls and rooms preserved.
