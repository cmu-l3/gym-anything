# GIMP Image Rotation Task (`image_rotation@1`)

## Overview

This task tests an agent's ability to use GIMP's rotate tool to correct image orientation by applying a specific rotation angle. The agent must select the rotate tool, input a precise angle value, and apply the rotation to straighten a tilted photograph. This represents a common image correction workflow used to fix camera tilt and improve photographic composition.

## Rationale

**Why this task is valuable:**
- **Parametric Transform Introduction:** Introduces angle-based transformations requiring numeric input, unlike simple flip operations
- **Photo Correction Skills:** Teaches essential workflow for fixing tilted or skewed photographs commonly encountered in photography
- **Precision Input:** Tests ability to enter specific numeric values for exact corrections rather than binary operations
- **Tool Parameter Control:** Demonstrates working with tool-specific parameters and preview systems
- **Real-world Application:** Critical skill for photography post-processing, document scanning, and architectural photography
- **Mathematical Understanding:** Requires grasp of rotation angles and directional conventions

**Skill Progression:** This task builds on basic transform concepts (like mirroring) to introduce parametric transformations with user-controlled input values.

## Skills Required

### A. Interaction Skills
- **Rotate Tool Selection:** Access the rotate tool from toolbox or use Shift+R shortcut
- **Angle Parameter Entry:** Input specific rotation values in tool options or rotation dialog
- **Dialog Interaction:** Work with rotation parameter dialogs and preview systems
- **Numeric Input:** Enter exact angle values (e.g., -15 degrees) with proper sign convention
- **Preview Assessment:** Evaluate rotation preview before final application
- **Transform Confirmation:** Apply transformations after preview validation

### B. GIMP Knowledge
- **Rotate Tool Behavior:** Understand how GIMP's rotate tool functions and its parameter system
- **Angle Convention:** Know GIMP's rotation direction convention (positive counterclockwise, negative clockwise)
- **Transform Application:** Understand preview mode vs. final application of transformations
- **Image Boundaries:** Recognize how rotation affects image canvas and potential cropping
- **Quality Settings:** Understand interpolation options available for rotation quality
- **Center Point Control:** Know default rotation center behavior and adjustment options

### C. Task-Specific Skills
- **Orientation Assessment:** Visually identify tilted horizons or skewed elements requiring correction
- **Angle Estimation:** Judge approximate correction angles needed for proper straightening
- **Horizon Alignment:** Understand principles of proper horizontal alignment in photography
- **Quality Evaluation:** Assess whether rotation improved image composition and correctness
- **Precision Application:** Apply exact angle corrections rather than approximate visual adjustments

## Task Steps

### 1. Image Analysis and Planning
- Examine the tilted landscape photo that opens automatically in GIMP
- Identify the horizon line or architectural elements that should be horizontal
- Estimate the approximate tilt angle requiring correction (typically 10-20 degrees)

### 2. Rotate Tool Selection
- Select the Rotate Tool from the toolbox or press Shift+R
- Observe that the cursor changes to rotation mode with angle indicator
- Check that tool options panel shows rotation parameters

### 3. Angle Parameter Configuration
- In the tool options panel, locate the angle input field
- Enter the correction angle value (e.g., -15.0 degrees for 15-degree clockwise correction)
- Ensure angle value uses proper sign convention for desired rotation direction

### 4. Initiate Rotation Preview
- Click on the image to activate the rotation tool and show preview
- Observe the preview grid and rotated image overlay
- Verify that horizon elements appear more level in the preview

### 5. Preview Assessment
- Examine the rotation preview to confirm proper angle correction
- Check that horizontal elements (horizon, buildings) appear properly aligned
- Verify rotation improves overall image composition and balance

### 6. Apply Transformation
- Click "Rotate" button in the transformation dialog to apply the rotation
- Confirm the transformation to make changes permanent
- Observe that the image is now rotated according to the specified angle

### 7. Quality Verification
- Examine the rotated image for proper horizon alignment and improved composition
- Verify that rotation was applied cleanly without significant quality degradation
- Ensure tilted elements are now properly straightened

### 8. Automatic Export
- The post-task hook will automatically export the result as "straightened_photo.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **rotation detection through cross-correlation analysis** combined with **horizon detection** to validate the correction:

### A. Rotation Angle Detection
- **Cross-Correlation Analysis:** Uses normalized cross-correlation to detect precise rotation between original and result
- **Multi-Angle Testing:** Tests correlation at various angles around expected correction to find optimal match
- **Subpixel Precision:** Achieves precise angle measurement through interpolation of correlation peak
- **Reference Validation:** Compares detected rotation against expected correction angle with reasonable tolerance

### B. Horizon Straightening Assessment
- **Edge Detection Analysis:** Uses Canny edge detection to identify linear features in both images
- **Hough Transform:** Applies line detection to identify major horizontal/vertical elements
- **Angle Distribution:** Analyzes the distribution of line angles before and after rotation
- **Straightening Effectiveness:** Quantifies improvement in horizontal alignment of key image elements

### C. Quality Preservation Verification
- **Interpolation Quality:** Assesses image quality preservation during rotation transformation
- **Boundary Handling:** Verifies proper handling of image boundaries and potential cropping
- **Artifact Detection:** Checks for rotation artifacts, aliasing, or quality degradation
- **Overall Integrity:** Ensures rotation maintains essential image characteristics and composition

### D. Mathematical Validation
- **Transform Accuracy:** Verifies applied rotation matches expected correction angle (±3° tolerance)
- **Pure Rotation Check:** Confirms transformation was rotation-only, not combined with scaling or shearing  
- **Center Point Validation:** Ensures rotation was applied around appropriate center point
- **Geometric Consistency:** Validates mathematical correctness of the applied transformation

### Verification Checklist
- ✅ **Correct Rotation Applied:** Detected rotation angle matches expected correction within ±3° tolerance
- ✅ **Horizon Improved:** Horizontal elements show measurable improvement in alignment
- ✅ **Image Quality Preserved:** No significant degradation, artifacts, or quality loss from rotation
- ✅ **Transform Completed:** Clear evidence that rotation transformation was successfully applied

### Scoring System
- **100%:** Perfect rotation with exact angle correction, excellent quality, and optimal horizon alignment
- **75-99%:** Good rotation with minor angle deviation (<2°) or minor quality issues
- **50-74%:** Adequate rotation applied but with notable angle inaccuracy (2-5°) or quality problems
- **0-49%:** Incorrect rotation angle (>5° error), poor quality, or transformation failure

**Pass Threshold:** 75% (requires good angle correction with acceptable quality preservation)

## Technical Implementation

### Files Structure
```
image_rotation/
├── task.json                  # Task configuration (8 steps, 120s timeout)
├── setup_rotation_task.sh     # Downloads tilted landscape photo, launches GIMP
├── export_rotation.sh         # Automates export as "straightened_photo"
├── verifier.py               # Cross-correlation rotation detection and horizon analysis
└── README.md                # This documentation
```

### Verification Features
- **Advanced Rotation Detection:** Uses cross-correlation analysis for precise angle measurement
- **Horizon Analysis:** Employs edge detection and Hough transforms for alignment assessment
- **Quality Preservation:** Evaluates interpolation quality and artifact detection
- **Mathematical Rigor:** Provides precise angle measurements with confidence scoring
- **Multi-criteria Evaluation:** Combines angle accuracy, quality preservation, and correction effectiveness

This task provides essential parametric transformation skills while maintaining clear verification criteria, representing real-world photo correction workflows commonly needed in photography and document processing applications.