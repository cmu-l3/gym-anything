# GIMP Clone Tool Duplication Task (`clone_duplicate@1`)

## Overview

This task tests an agent's ability to use GIMP's Clone tool to duplicate part of an image to another location. The agent must select the Clone tool, set a source point by Ctrl+clicking on an interesting image element, then paint/clone that element to a different area of the image. This represents a fundamental retouching and image manipulation technique commonly used in photo editing, object duplication, and creative composition.

## Rationale

**Why this task is valuable:**
- **Clone Tool Mastery:** Introduces one of GIMP's most powerful and versatile retouching tools
- **Source-Destination Concept:** Teaches the fundamental principle of sampling and applying image data
- **Precise Coordination:** Requires accurate clicking and painting motions for proper cloning
- **Creative Duplication:** Enables artistic composition through selective element repetition
- **Real-world Application:** Essential for photo retouching, object removal/addition, and artistic effects
- **Foundation Skill:** Establishes concepts needed for advanced retouching and healing techniques

**Skill Progression:** This task bridges basic tool usage with advanced retouching workflows, introducing the concept of sampling-based image manipulation.

## Skills Required

### A. Interaction Skills
- **Tool Selection:** Locate and activate the Clone tool from toolbox or shortcut (C)
- **Source Sampling:** Use Ctrl+Click to set the clone source point accurately
- **Brush Painting:** Apply cloned content through brush-like painting motions
- **Coordinate Management:** Maintain awareness of source-destination relationships during cloning
- **Pressure Control:** Apply appropriate brush pressure and size for effective cloning

### B. GIMP Knowledge
- **Clone Tool Behavior:** Understand how the Clone tool samples and reproduces image content
- **Source Point Concept:** Know how Ctrl+clicking establishes the sampling reference point
- **Brush Settings:** Understand how brush size and opacity affect clone application
- **Real-time Sampling:** Know that clone source updates dynamically relative to brush position
- **Layer Interaction:** Understand how cloning interacts with the current layer

### C. Task-Specific Skills
- **Element Identification:** Recognize interesting image features suitable for duplication
- **Spatial Planning:** Choose appropriate locations for duplicated elements
- **Source Selection:** Position clone source to capture complete, useful image content
- **Application Technique:** Apply cloned content smoothly and naturally
- **Quality Assessment:** Evaluate whether cloned elements integrate well with the surrounding image

## Task Steps

### 1. Image Analysis
- Examine the image that opens automatically in GIMP (likely a landscape or object scene)
- Identify an interesting element that would look good duplicated (e.g., a flower, cloud, or decorative object)
- Plan where the duplicate should be positioned for best visual effect

### 2. Clone Tool Selection
- Click on the Clone tool in the toolbox or press C key
- Observe cursor change to crosshairs indicating clone mode is active
- Check that appropriate brush size is selected (adjust if necessary)

### 3. Set Clone Source
- Position cursor over the center of the element to be duplicated
- Hold Ctrl key and click to set the clone source point
- Observe that the cursor may show a preview or indication of the source area
- Release Ctrl key after setting the source

### 4. Position for Cloning
- Move cursor to the location where the duplicate should appear
- Choose an area with appropriate background that won't conflict with the cloned content
- Ensure adequate space for the complete element to be duplicated

### 5. Apply Clone Content
- Click and drag (or use multiple clicks) to paint the cloned content
- Apply enough coverage to reproduce the complete source element
- Monitor the result to ensure the cloned element appears correctly
- Continue painting until the duplication is complete and well-integrated

### 6. Quality Check
- Examine the cloned element for completeness and visual quality
- Verify that the duplicate looks natural and properly integrated
- Ensure the source element remains intact and unchanged

### 7. Automatic Export
- The post-task hook will automatically export the result as "cloned_element.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **template matching and duplication detection** to identify successful cloning:

### A. Duplication Detection
- **Template Matching:** Uses computer vision techniques to find similar regions in the image
- **Cross-Correlation Analysis:** Identifies areas with high similarity to detect duplicated content
- **Feature Point Comparison:** Analyzes distinctive features to confirm duplication occurred
- **Pattern Recognition:** Uses image processing algorithms to detect repeated visual patterns

### B. Clone Quality Assessment
- **Similarity Measurement:** Calculates correlation between original and cloned elements
- **Coverage Analysis:** Ensures adequate area was cloned to represent complete duplication
- **Integration Quality:** Assesses how well cloned content blends with surrounding areas
- **Completeness Check:** Verifies that recognizable, substantial content was duplicated

### C. Spatial Analysis
- **Source Preservation:** Confirms original element remains unchanged
- **Location Validation:** Ensures cloned content appears in a different image location
- **Reasonable Placement:** Validates that duplication occurred in appropriate areas
- **Non-overlap Verification:** Ensures cloned content doesn't directly overlay the source

### D. Change Detection
- **Image Modification:** Confirms significant changes occurred through the cloning process
- **Content Addition:** Verifies that new visual content was added to the image
- **Duplication Evidence:** Ensures changes represent actual content duplication, not random modification
- **Quality Threshold:** Maintains standards for meaningful, recognizable cloning

### Verification Checklist
- ✅ **Duplication Detected:** Clear evidence of repeated visual content in different image locations
- ✅ **Adequate Coverage:** Cloned area covers sufficient pixels to represent meaningful duplication (≥200 pixels)
- ✅ **High Similarity:** Cloned content shows strong correlation (≥0.7) with source area
- ✅ **Spatial Separation:** Cloned content positioned away from source location (≥50 pixel minimum distance)

### Scoring System
- **100%:** Perfect cloning with excellent duplication quality and placement
- **75-99%:** Good cloning with minor issues in coverage, quality, or positioning
- **50-74%:** Recognizable cloning attempt but with notable quality or technique problems
- **0-49%:** Insufficient or failed cloning operation

**Pass Threshold:** 75% (requires clear, well-executed element duplication)

## Technical Implementation

### Files Structure
```
clone_duplicate/
├── task.json               # Task configuration (7 steps, 120s timeout)
├── setup_clone_task.sh     # Downloads scene image with elements to clone, launches GIMP
├── export_clone.sh         # Automates export as "cloned_element"
├── verifier.py            # Template matching and duplication detection verification
└── README.md             # This documentation
```

### Verification Features
- **Advanced Computer Vision:** Uses OpenCV template matching for robust duplication detection
- **Spatial Relationship Analysis:** Validates proper source-destination separation and positioning
- **Quality Metrics:** Assesses correlation strength and coverage adequacy objectively
- **Multi-scale Detection:** Analyzes various template sizes to catch different cloning approaches
- **False Positive Filtering:** Distinguishes intentional cloning from accidental similarity

This task introduces agents to sampling-based image manipulation, a fundamental concept in digital image editing that underlies many advanced retouching and creative techniques. The Clone tool represents a perfect bridge between basic painting operations and sophisticated content-aware editing workflows.