# GeoGebra Environment - Testing Evidence

## Test Date: 2026-02-02 (Updated with Audit Fixes v3)

## Environment Setup Verification

### Installation and Launch
- **Status**: PASSED
- **Evidence**: GeoGebra Classic launches successfully with proper UI components
- **SSH Port**: Environment provides SSH access for interaction (port determined by env.json)
- **Resolution**: 1920x1080
- **Display**: :1
- **User Account**: ga (password: password123)

### UI Components Verified
1. Main toolbar with geometry tools
2. Algebra panel (shows Free Objects, Dependent Objects)
3. Graphics view with coordinate system
4. Input bar at bottom
5. Menu bar (File, Edit, View, Perspectives, Options, Tools, Window, Help)

## Task 1: Construct Equilateral Triangle

### Task Requirements
- Use GeoGebra tools to construct an equilateral triangle
- All three sides must be equal length
- All three angles must be 60° (within ±2° tolerance) - **explicitly stated in task description**
- **Must use Polygon tool** to connect the three vertices (task description now includes instructions: "select Polygon from toolbar, then click the three vertices in order and close by clicking the first vertex again")
- Save as `equilateral_triangle.ggb` in `~/Documents/GeoGebra/projects/`

### Verifier Logic (4 criteria, 25 points each)

1. **GeoGebra file exists** - File found at expected path or recent .ggb file
2. **File created during task** - Timestamp validation prevents pre-made file attacks
3. **Construction elements present** - At least 3 points AND (segments OR polygon)
4. **Equilateral triangle verified** - Polygon vertices form equilateral triangle with angles in [58°, 62°]

**STRICT POLYGON REQUIREMENT**: The verifier now ONLY considers polygon vertices for triangle verification. Creating random points hoping 3 accidentally form equilateral will NOT work - the agent MUST create a proper polygon construction.

### Mathematical Verification of Baseline

The `evidence_geogebra.xml` file contains a mathematically perfect equilateral triangle:

**Coordinates**:
- A = (0, 0)
- B = (4, 0)
- C = (2, 3.4641016151377544) [which is exactly (2, 2√3)]

**Verification Calculations**:
```
Side AB = √[(4-0)² + (0-0)²] = √16 = 4.0
Side BC = √[(4-2)² + (0-3.464...)²] = √[4 + 12] = √16 = 4.0
Side CA = √[(2-0)² + (3.464...-0)²] = √[4 + 12] = √16 = 4.0

All sides = 4.0 (EQUAL)

Angle at A: cos⁻¹[(AB·AC)/(|AB||AC|)] = 60.0°
Angle at B: cos⁻¹[(BA·BC)/(|BA||BC|)] = 60.0°
Angle at C: cos⁻¹[(CA·CB)/(|CA||CB|)] = 60.0°

All angles = 60.0° (EQUAL)
```

**Expected Verifier Result for Perfect Triangle**:
- `passed`: true
- `score`: 100
- `feedback`: "GeoGebra file found | File created during task (timestamp verified) | Construction has 3 points, segments/polygon present | Equilateral triangle verified! Vertices: ['A', 'B', 'C'] | Sides: 4.00, 4.00, 4.00 | Angles: 60.0°, 60.0°, 60.0°"

### Test Cases

| Test Case | Input | Expected Result |
|-----------|-------|-----------------|
| Perfect equilateral | A=(0,0), B=(4,0), C=(2,2√3) | PASS, score=100 |
| Slightly off (within tolerance) | Angles 58.5°, 60°, 61.5° | PASS, score=100 |
| Outside tolerance | Angles 57°, 60°, 63° | FAIL (57° < 58°, 63° > 62°) |
| No polygon | 3 separate points, no Polygon command | FAIL (requires polygon construction) |
| Only 2 points | Missing third vertex | FAIL, score≤50 |

## Task 2: Graph Quadratic Function

### Task Requirements
- Graph the quadratic function f(x) = x² - 4x + 3
- Use the input bar to enter the function (type: x^2 - 4x + 3)
- **MUST mark at least 3 of 4 key points** (this is mandatory for passing)
- Agent must calculate coordinates mathematically:
  - Vertex: Use x = -b/2a formula, then evaluate f(x)
  - X-intercepts: Solve f(x) = 0 (factor or use quadratic formula)
  - Y-intercept: Evaluate f(0)
- Save as `quadratic_graph.ggb` in `~/Documents/GeoGebra/projects/`

**Educational Design (v5)**: Task description no longer provides exact coordinates. Agent must apply mathematical knowledge to find:
- Vertex at (2, -1) using x = -(-4)/(2×1) = 2, then f(2) = 4 - 8 + 3 = -1
- X-intercepts at (1, 0) and (3, 0) by factoring: (x-1)(x-3) = 0
- Y-intercept at (0, 3) by computing f(0) = 0 - 0 + 3 = 3

### Verifier Logic (5 criteria, 20 points each)

1. **GeoGebra file exists**
2. **File created during task** - Timestamp validation
3. **Quadratic function detected** - MUST be a quadratic (x²), not just any function
4. **Correct quadratic** - Matches x² - 4x + 3 or factored form (x-1)(x-3)
5. **Key points marked** - At least 3 of: vertex, root1, root2, y-intercept (within ±0.1 tolerance)

**Critical Fix (v4)**: Criterion 3 now requires a QUADRATIC function specifically. Previously, any function would satisfy criterion 3, allowing agents to pass with wrong functions like sin(x).

**Point Tolerance**: Key points are matched with ±0.1 unit tolerance (consistent with task.json metadata).

**Hard Requirement**: To pass (passed=true), the agent must BOTH:
- Score ≥ 75%
- Have marked key points (criterion 5 must be satisfied)

This makes key point marking mandatory, not optional.

## CUA Integration (ask_cua.py)

The `ask_cua.py` script uses a VLM to identify GUI element coordinates:
- Input: Screenshot at actual resolution (e.g., 1920x1080)
- Output: Coordinates normalized to 1280x720 scale
- **Important**: Multiply returned coordinates by 1.5 for 1920x1080 displays
- Model: databricks-claude-sonnet-4-5 via Databricks endpoint

### Usage Pattern
1. Take screenshot from environment
2. Call ask_cua.py with question about coordinate location
3. Parse returned coordinates and scale to actual resolution
4. Execute xdotool commands via SSH

## Security Mitigations

### 1. Pre-computed Coordinate Attacks
- **Problem**: Agent could use pre-computed coordinates without visual understanding
- **Mitigation 1**: Timestamp validation ensures file was created during task window
- **Mitigation 2**: Viewport randomization - setup script randomly pans and zooms the view
  - Controlled by `RANDOMIZE_VIEWPORT` environment variable (default: enabled)
  - Random pan offset: -50 to +50 pixels
  - Random zoom: -1, 0, or +1 scroll wheel clicks
  - Recorded to `/tmp/viewport_randomization` for debugging

### 2. Random Point Exploitation
- **Problem**: Agent could create many random points hoping 3 accidentally form equilateral
- **Mitigation**: STRICT polygon-only mode - verifier ONLY uses polygon vertices
  - If no polygon exists, the triangle criterion automatically fails
  - Agent MUST use Polygon tool to connect vertices properly

### 3. Coordinate Precision
- **Problem**: VLM coordinate estimation has inherent uncertainty (~10-20 pixel error)
- **Impact**: Triangles created via GUI may not be perfectly equilateral
- **Acceptable**: The ±2° tolerance accounts for this while still requiring genuine effort

### 4. Multiple GeoGebra Windows
- **Problem**: Sometimes rename dialogs or multiple windows appear
- **Solution**: Use input bar commands instead of clicking when possible

## Checklist Summary

- [x] Installation script completes without errors
- [x] Setup script completes without errors
- [x] Application is visible in screenshot
- [x] Application is in correct initial state
- [x] Task setup runs without errors
- [x] Export script produces valid JSON
- [x] Verifier can read and process the result
- [x] Verification returns expected result for incomplete work
- [x] Verification returns passed=true for mathematically perfect equilateral triangle
- [x] Timestamp validation prevents pre-made file attacks
- [x] Viewport randomization prevents coordinate memorization
- [x] Strict polygon mode prevents random point exploitation
- [x] Key points are a hard requirement for Task 2
- [x] Task description includes tolerance specification

## Screenshots

1. `geogebra_initial_state.png` - Fresh GeoGebra with empty canvas
2. `01_point_tool_selected.png` - Point tool successfully selected
3. `02_three_points_created.png` - Three points created in GeoGebra
4. `03_geogebra_with_points.png` - Application state showing points
5. `evidence_geogebra.xml` - Mathematically verified perfect equilateral triangle (A=(0,0), B=(4,0), C=(2,2√3))

## Files Modified in Audit Fixes

### Shared Scripts
- `scripts/task_utils.sh`: Added `randomize_geogebra_viewport()` function

### Task 1 (construct_equilateral_triangle)
- `task.json`: Added "(within ±2° tolerance)" to task description
- `setup_task.sh`: Added task_start_time recording, viewport randomization
- `export_result.sh`: Added timestamp fields, fixed grep -c bug, added fallback trap
- `verifier.py`: Added timestamp validation, STRICT polygon-only mode, proper angle tolerance

### Task 2 (graph_quadratic_function)
- `setup_task.sh`: Added task_start_time recording, viewport randomization
- `export_result.sh`: Added timestamp fields, fixed grep -c bug, added fallback trap
- `verifier.py`: Added timestamp validation, made key points a hard requirement

### Evidence Documentation
- `evidence_geogebra.xml`: Created mathematically correct perfect equilateral triangle
- `README.md`: Updated with accurate mathematical verification and test cases
