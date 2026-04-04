# Technology Radar Quarterly Review (`tech_radar_quarterly_review@1`)

## Overview
A VP of Engineering needs to create a Technology Radar diagram (inspired by the ThoughtWorks Technology Radar format) for their company's quarterly engineering review meeting. Starting from a pre-built empty radar template in draw.io, the agent must plot 20 real-world technologies into their correct quadrant and ring positions, apply color-coding based on movement status, add a legend, and export the result as PNG. This task tests precise shape placement, labeling, bulk styling, legend creation, and diagram export in draw.io.

## Rationale
**Why this task is valuable:**
- Tests precise spatial placement of multiple labeled shapes within a structured layout
- Requires reading and interpreting a specification file and translating data to visual form
- Exercises draw.io's core shape creation, positioning, text editing, and fill color features
- Tests multi-step workflow: read spec → create shapes → position → style → legend → export

**Real-world Context:** Technology radar diagrams are used by engineering organizations worldwide to communicate technology adoption strategy. CTOs and engineering leaders create these quarterly to align teams on which technologies to invest in, experiment with, or phase out.

## Task Description

**Goal:** Populate an empty technology radar template with 20 technologies from a provided assessment file, applying correct quadrant/ring placement and movement-status color coding, then add a legend and export to PNG.

**Starting State:**
- draw.io is open with `~/Diagrams/tech_radar_template.drawio` loaded
- The template contains an empty radar: 4 concentric rings (Adopt innermost, Hold outermost), 4 quadrant labels, and a title
- `~/Desktop/tech_assessment_Q4_2024.txt` contains 20 technology entries with quadrant, ring, and movement status

**Expected Actions:**
1. Read the technology assessment file `~/Desktop/tech_assessment_Q4_2024.txt`
2. For each of the 20 technologies, create a shape (small rounded rectangle or ellipse) in the diagram
3. Label each shape with the technology name
4. Position each shape in the correct quadrant AND ring of the radar
5. Apply fill colors based on movement status:
   - **New** (first appearance on radar): Green (`#00CC00`)
   - **Moved In** (moved to a closer ring): Blue (`#3399FF`)
   - **Moved Out** (moved to a farther ring): Orange (`#FF9900`)
   - **No Change**: Gray (`#CCCCCC`)
6. Create a legend in the bottom-right area of the diagram showing the 4 movement status colors with labels
7. Save the diagram as `~/Diagrams/tech_radar_Q4_2024.drawio` (or overwrite the template)
8. Export as PNG to `~/Diagrams/exports/tech_radar_Q4_2024.png`

**Final State:** A completed technology radar diagram with 20 labeled, correctly-placed, color-coded technology items, a legend, saved as both `.drawio` and `.png`.

## Verification Strategy

### Primary Verification: XML Content Analysis
Parse the saved `.drawio` XML file to verify:
- All 20 technology names appear as cell labels/values in the diagram
- Total shape count indicates sufficient items added
- Distinct fill color hex values present matching the requirements
- Legend-related text labels exist

### Secondary Verification: Export & File Checks
- PNG file exists and has non-trivial size
- File modification timestamps prove work was done during task window

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| File modified | 5 | Anti-gaming check |
| Technology Labels | 30 | Correct names present in diagram |
| Color Coding | 15 | At least 3 distinct status colors used |
| Legend Created | 10 | Legend text labels present |
| Shape Count | 10 | Sufficient shapes added |
| PNG Export | 20 | Valid PNG output created |
| Visual Verification | 10 | VLM confirms visual structure |
| **Total** | **100** | |