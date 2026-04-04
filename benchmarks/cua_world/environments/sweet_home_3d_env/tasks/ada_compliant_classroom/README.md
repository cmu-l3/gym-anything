# ada_compliant_classroom

**Occupation**: Architect
**Industry**: Educational Architecture
**Difficulty**: Extremely Hard

## Task Description

Design an ADA-compliant multi-purpose classroom for a community college continuing-education wing. The building shell is open in Sweet Home 3D. The agent must use **4 distinct Sweet Home 3D features** to create a fully accessible classroom accommodating 24 students:

1. **Furniture placement** -- student desks and chairs, instructor station, resource shelving, restroom fixtures
2. **Wall creation** -- partition walls to define instructor area, student seating zone, resource alcove, and staff preparation area
3. **Door/window placement** -- wheelchair-accessible doorways between zones
4. **Dimension annotation** -- dimension lines documenting key clearance widths for ADA code review

## Features Used

| Feature | Used |
|---------|------|
| Furniture catalog placement | Yes |
| Wall creation | Yes |
| Door/window placement | Yes |
| Dimension annotation | Yes |

## Scoring

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| C1: Student seating | 25 | >=24 chairs + >=12 desks (partial: >=16+8 for 15, >=8+4 for 8) |
| C2: Walls + doors | 20 | >=2 new walls + >=2 doors/windows (partial: >=1 each for 10) |
| C3: Resource zone | 20 | >=4 shelves + >=1 instructor desk (partial: >=2 shelves for 10) |
| C4: Dimension annotations | 15 | >=2 new dimension lines (partial: >=1 for 7) |
| C5: Restrooms + total + save | 20 | >=2 toilets (5), >=2 sinks (5), >=50 items (5), file changed (5) |
| **Total** | **100** | **Pass: 70** |

Wrong-target gate: <10 furniture items = score 0.

## Starter File

`ada_classroom_starter.sh3d` -- building shell with walls and rooms preserved, all furniture removed.

## Baseline Defaults

```json
{
  "furniture_count": 0,
  "starter_md5": null,
  "wall_count": 0,
  "dimension_count": 0,
  "door_window_count": 0
}
```

## Export Parser

The `export_result.sh` script extracts from the `.sh3d` XML:

- **Furniture** with keyword categorization:
  - Chairs: chair, stool, seat, armchair, bench
  - Desks: desk, table, workstation, podium, lectern, counter, station
  - Shelves: shelf, shelving, bookcase, bookshelf, cabinet, cupboard, wardrobe, storage, rack
  - Toilets: toilet, wc, lavatory, bidet
  - Sinks: sink, basin, washbasin, lavabo
- **Walls** (`wall` elements)
- **Rooms** (`room` elements)
- **Labels** (`label` elements with text)
- **Doors/windows** (`pieceOfFurniture` with `doorOrWindow="true"`)
- **Dimension lines** (`dimensionLine` elements)
- **Deltas**: `new_walls`, `new_doors`, `new_dimensions` computed against baseline
