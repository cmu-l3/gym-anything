# open_plan_office_renovation

**Occupation**: Interior Designer
**Industry**: Commercial Interior Design
**Difficulty**: Extremely Hard

## Task Description

Convert a residential apartment into a modern open-plan coworking office for a tech startup with 12 employees. The apartment shell is pre-drafted in Sweet Home 3D with all residential furniture removed. The agent must:

1. **Define room zones** for each functional area (executive, collaborative workspace, reception, lounge) so the floor plan is self-documenting.
2. **Apply distinct floor colors/textures** to visually differentiate each zone.
3. **Install doors/windows** where privacy or noise separation is needed between zones.
4. **Furnish the entire space** to professional office standards with appropriate seating, work surfaces, storage, lighting, and decorative elements.

## Features Required

This task exercises four Sweet Home 3D capabilities:

| Feature | How It Is Tested |
|---------|-----------------|
| `furniture_placement` | Desks, chairs, sofas, tables, bookcases, appliances, decor items |
| `room_definition` | Named room boundaries for each functional zone |
| `door_window_placement` | Doors/windows placed for privacy between zones |
| `floor_color` | Distinct floor colors or textures applied to differentiate zones |

## Scoring

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| C1: Room zones | 20 | >=3 new rooms defined with names or floor colors; >=2 rooms with floor color |
| C2: Office furniture | 25 | >=8 desks + >=8 chairs |
| C3: Doors + reception decor | 20 | >=2 doors/windows placed + >=3 decor items (lamps/plants/art) |
| C4: Lounge/kitchenette | 20 | >=1 sofa + >=1 table + >=2 appliances |
| C5: Diversity + total + save | 15 | >=10 distinct types, >=35 total items, file changed |
| **Total** | **100** | **Pass: 70** |

### Partial Credit

- **C1**: 10 pts if >=2 rooms or >=1 floor color applied
- **C2**: 12 pts if >=4 desks + >=4 chairs
- **C3**: 10 pts if doors OR decor requirement met (but not both)
- **C4**: 10 pts if >=1 sofa or (>=1 table + >=1 appliance)
- **C5**: 5 pts per sub-requirement met (types, total count, file changed)

### Wrong-Target Gate

If fewer than 8 furniture items are found, the score is automatically 0.

## Starter File

`open_plan_office_starter.sh3d` -- stripped from a furnished apartment example. All furniture removed; walls, rooms, and doors preserved as the building shell.

## Export Pipeline

The `export_result.sh` script parses the `.sh3d` file (a ZIP containing `Home.xml`) and extracts:
- Furniture items with keyword-based categorization (desks, chairs, sofas, tables, bookcases, appliances, lamps, plants, art)
- Room definitions with names and floor color/texture attributes
- Door/window items (via `doorOrWindow="true"` attribute on `pieceOfFurniture` elements)
- Wall count and label text
- Baseline comparison for file-changed detection
