# GIMP Clone Tool Application Task (`clone_stamp@1`)

## Overview

This task tests an agent's ability to use GIMP's Clone Tool (also called Stamp Tool) to copy texture or content from one area of an image to another. The agent must activate the clone tool, set a source point using Ctrl+click, and paint over a target area to replicate the source texture. This represents essential photo retouching and texture manipulation skills used in professional image editing.

## Rationale

**Why this task is valuable:**
- **Fundamental Retouching Tool:** Clone tool is essential for photo restoration, blemish removal, and object removal
- **Brush-based Interaction:** Introduces painting/brush-based tools distinct from selection-based workflows
- **Source-Target Coordination:** Tests spatial reasoning by coordinating source and destination areas
- **Texture Understanding:** Requires recognizing and replicating visual patterns and textures
- **Real-world Application:** Heavily used in portrait retouching, landscape extension, object removal, and photo restoration
- **Foundation for Advanced Editing:** Establishes concepts needed for healing brush, perspective clone, and other retouching tools

**Skill Progression:** This task introduces brush-based tools and sampling concepts, bridging selection-based operations with more sophisticated retouching workflows.

## Skills Required

### A. Interaction Skills
- **Tool Selection:** Locate and activate Clone Tool from toolbox (C key)
- **Ctrl+Click Sampling:** Hold Ctrl and click to set clone source point
- **Brush Painting:** Click and drag to paint cloned texture onto target area
- **Crosshair Tracking:** Monitor source crosshair while painting to understand sampling behavior
- **Brush Size Adjustment:** Optionally adjust brush size for appropriate coverage
- **Sustained Interaction:** Maintain painting motion until target area is adequately covered

### B. GIMP Knowledge
- **Clone Tool Concepts:** Understand the tool copies pixels from source to destination
- **Source Point Setting:** Know that Ctrl+click establishes the reference point
- **Offset Relationship:** Understand that source and paint locations maintain relative offset
- **Brush System:** Recognize clone tool uses brush settings (size, hardness, spacing)
- **Tool Options:** Navigate clone tool options panel for settings adjustment
- **Alignment Modes:** Understand aligned vs. non-aligned cloning behavior

### C. Task-Specific Skills
- **Texture Selection:** Identify appropriate source areas with suitable texture/pattern
- **Target Assessment:** Recognize areas that need texture filling or object removal
- **Spatial Planning:** Plan source point placement to avoid unintended pattern disruption
- **Seamless Blending:** Apply clone strokes to achieve natural-looking results
- **Pattern Awareness:** Avoid obvious repetition or unnatural texture tiling
- **Coverage Judgment:** Know when target area is adequately filled

## Task Steps

### 1. Image Analysis
- Examine the image that opens automatically in GIMP (landscape with an object to remove)
- Identify the target area marked in red that needs to be filled or covered
- Identify nearby suitable source texture (e.g., grass, sky, water)

### 2. Activate Clone Tool
- Select the Clone Tool from the toolbox or press C key
- Observe cursor changes to indicate clone mode is active
- Check tool options to ensure reasonable brush size (e.g., 50-100 pixels)

### 3. Set Clone Source Point
- Position cursor over the suitable source texture area
- Hold Ctrl key (cursor shows crosshair icon)
- Click once to set the source point
- Release Ctrl key

### 4. Navigate to Target Area
- Move cursor to the red-marked target area that needs to be filled
- Observe that a crosshair appears showing where pixels will be sampled from
- Verify the source-target relationship makes sense visually

### 5. Paint Cloned Texture
- Click and drag over the red-marked target area to paint the cloned texture
- Continue painting with multiple strokes if needed to cover the entire target region
- Observe the source crosshair moving in parallel to show sampling location
- Ensure adequate coverage without obvious repetition patterns

### 6. Refine Coverage
- Continue painting until the red-marked target area is completely covered
- Blend edges if necessary by painting more gently at boundaries
- Verify the result looks natural and seamless

### 7. Automatic Export
- The post-task hook will automatically export the result as "cloned_result.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **multi-region similarity analysis and change detection** to validate successful cloning:

### A. Change Detection
- **Pixel Difference Analysis:** Compute pixel-wise differences between original and result images
- **Significant Change Regions:** Identify areas with substantial modification (threshold: >20 intensity units)
- **Target Area Coverage:** Verify that changes occurred in the designated target region
- **Change Magnitude:** Ensure modifications are significant enough to represent cloning activity

### B. Source-Target Similarity Analysis
- **Texture Correlation:** Measure similarity between source region and modified target region
- **Pattern Matching:** Use structural similarity between source and target areas
- **Feature Comparison:** Analyze whether target region now shares visual characteristics with source
- **Similarity Threshold:** Require moderate similarity indicating successful texture replication

### C. Coverage Validation
- **Area Calculation:** Measure the size of the modified region
- **Minimum Coverage:** Ensure target area has been adequately painted over (≥70% coverage)
- **Reasonable Extent:** Verify changes are localized to target area, not excessive
- **Completeness Check:** Confirm the intended area is fully addressed

### Verification Checklist
- ✅ **Target Area Modified:** Significant pixel changes detected in designated target region
- ✅ **Source-Target Similarity:** Modified region shows similarity to source texture
- ✅ **Adequate Coverage:** Target area sufficiently covered by clone painting
- ✅ **Natural Appearance:** No obvious artifacts, edges blend reasonably well

### Scoring System
- **100%:** All 4 criteria met (excellent cloning with natural appearance)
- **75-99%:** 3/4 criteria met (good cloning with minor imperfections)  
- **50-74%:** 2/4 criteria met (recognizable cloning but significant issues)
- **0-49%:** <2 criteria met (cloning failed or insufficient)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure