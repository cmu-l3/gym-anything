# solar_facility_site_plan

**Occupation**: Solar Energy Systems Engineer
**Industry**: Renewable Energy / Solar Power
**Difficulty**: Extremely Hard

## Task Description

Transform a residential villa into a solar installation company's operations center. The agent must use **4 distinct Sweet Home 3D features**:

1. **Wall creation** -- build partition walls to divide the open floor plan into functional zones
2. **Room/label placement** -- define rooms or add text labels to identify each zone
3. **Furniture placement** -- furnish the control room, storage, training room, break room, and restrooms
4. **Spatial reasoning** -- create a layout that makes professional sense for a field operations center

## Features Used

| Feature | Used |
|---------|------|
| Furniture catalog placement | Yes |
| Wall creation | Yes |
| Room definition / naming | Yes |
| Label placement | Yes |

## Scoring

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| C1: Partition walls | 20 | >=3 new walls beyond baseline |
| C2: Control/training furniture | 25 | >=4 desks, >=2 shelves, >=10 chairs |
| C3: Zone identification | 20 | >=3 rooms defined or labels placed |
| C4: Storage + break room | 20 | >=3 shelves, >=1 appliance, >=6 chairs |
| C5: Restrooms + total + save | 15 | >=2 toilets, >=30 total, file changed |
| **Total** | **100** | **Pass: 70** |

Wrong-target gate: <8 furniture items = score 0.

## Starter File

Stripped from `SweetHome3DExample7.sh3d` (contemporary villa). All furniture removed; walls and rooms preserved.
