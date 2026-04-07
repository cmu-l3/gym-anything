# polygon_explorer_program

## Task Overview

**Environment**: Sugar Learning Platform (OLPC)
**Difficulty**: Hard
**Occupation**: OLPC deployment coordinator / elementary curriculum developer
**Application**: TurtleBlocks (visual block-based programming)

## Domain Context

OLPC (One Laptop Per Child) deployment coordinators and curriculum developers create TurtleBlocks programming lessons for elementary students. TurtleBlocks is a visual programming language where students drag and snap colored blocks to build programs that control a turtle drawing on screen — similar to Logo programming. Polygon construction is a standard 4th-grade math-through-programming lesson.

## Goal

Build a TurtleBlocks program that draws two geometric shapes in sequence:
1. **Square**: 4 sides of length 100, turning 90° at each corner (repeat 4 times)
2. **Equilateral triangle**: 3 sides of length 100, turning 120° at each corner (repeat 3 times)

Both shapes must be connected after the `start` block. The program must be saved as `/home/ga/Documents/polygon_explorer.ta`.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| File `polygon_explorer.ta` saved and modified during task | 15 |
| File has content (>50 bytes) | 5 |
| `start` block present | 5 |
| `repeat` block present | 10 |
| `forward` block present | 10 |
| `repeat(4)` for square | 15 |
| `right(90)` for square corners | 15 |
| `repeat(3)` for triangle | 15 |
| `right(120)` for triangle corners | 15 |
| **Total** | **105** (capped at 100) |

**Pass threshold**: score ≥ 70 AND both shapes structurally present (repeat_4+right_90 AND repeat_3+right_120)

## Verification Strategy

1. `setup_task.sh` records a start timestamp and opens TurtleBlocks on a blank canvas
2. `export_result.sh` checks `/home/ga/Documents/polygon_explorer.ta`, parses the `.ta` JSON format (array of block arrays), and extracts block names and numeric values
3. `verifier.py` reads `/tmp/polygon_explorer_program_result.json` and checks for required block types and specific numeric values (4, 90, 3, 120, 100)

## TurtleArt `.ta` File Format Reference

```json
[
  [0, "start", x, y, [null, 1]],
  [1, "repeat", x, y, [0, 2, 3, null]],
  [2, ["number", 4], x, y, [1, null]],
  [3, "forward", x, y, [1, 4, 5]],
  [4, ["number", 100], x, y, [3, null]],
  ...
]
```

- Block type is `item[1]` — either a string (block name) or `["type", value]` for literals
- Numeric values appear as `["number", value]` in the block array

## Edge Cases

- Agent may save via TurtleBlocks' File menu (Save As) or via the Sugar Journal keep button; only the filesystem path `/home/ga/Documents/polygon_explorer.ta` is verified
- Agent may use `left` instead of `right` blocks (TurtleBlocks has both); both are acceptable since `right(90)` and `right(120)` are the expected values
- The `.ta` file must be valid JSON; a corrupted save will score 0 on content checks
