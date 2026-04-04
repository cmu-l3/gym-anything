# GIMP Autocrop Image Task (`autocrop@1`)

## Overview

This task tests an agent's ability to use GIMP's intelligent autocrop feature to automatically remove uniform borders or empty space around an image. The agent must navigate to the autocrop function and apply it to trim unnecessary margins, resulting in a tighter composition focused on the actual content. This represents a common image optimization workflow used in photo editing, document scanning, and web graphics preparation.

## Rationale

**Why this task is valuable:**
- **Intelligent Automation:** Introduces GIMP's automatic image analysis capabilities
- **Composition Optimization:** Teaches how to eliminate wasted space and improve visual focus
- **Workflow Efficiency:** Demonstrates time-saving automatic operations vs. manual cropping
- **Real-world Relevance:** Commonly used for scanned documents, screenshots, product photography
- **Simple Yet Powerful:** One-command operation that performs sophisticated analysis
- **Foundation Skill:** Prepares agents for other automatic enhancement features

**Skill Progression:** This task introduces intelligent automatic operations, bridging manual tool usage (like crop_resize) with AI-assisted editing features.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through menu structure (`Image → Autocrop Image` or `Image → Crop to Content`)
- **Single-click Operation:** Execute command without additional dialog interaction
- **Visual Assessment:** Recognize when autocrop has successfully removed unwanted borders
- **Result Verification:** Compare before/after to confirm appropriate cropping occurred

### B. GIMP Knowledge
- **Autocrop Concept:** Understand that autocrop automatically detects and removes uniform borders
- **Image Menu System:** Navigate GIMP's image manipulation menu hierarchy
- **Automatic vs. Manual:** Distinguish between manual crop tool and automatic autocrop
- **Content Detection:** Understand how GIMP identifies "empty" vs. "content" regions
- **Immediate Application:** Know that autocrop applies instantly without parameter dialogs

### C. Task-Specific Skills
- **Border Recognition:** Identify images that have unnecessary uniform borders/margins
- **Content Identification:** Understand what constitutes the "main content" to be preserved
- **Composition Assessment:** Evaluate whether autocrop improved the image composition
- **Appropriate Use:** Recognize when autocrop is suitable vs. when manual cropping is better

## Task Steps

### 1. Initial Image Examination
- Examine the image that opens automatically in GIMP (image with visible uniform borders)
- Identify the main content area surrounded by empty/uniform space
- Note the current image dimensions and visible border regions

### 2. Locate Autocrop Function
- Navigate to the Image menu in the menu bar
- Look for "Autocrop Image" or "Crop to Content" option
- Prepare to execute the automatic cropping operation

### 3. Execute Autocrop
- Click on "Autocrop Image" (or "Crop to Content" depending on GIMP version)
- Observe that the operation executes immediately without dialog
- Notice the canvas automatically adjusts to remove uniform borders

### 4. Verify Result
- Confirm that uniform border regions have been removed
- Check that the main content remains fully visible and centered
- Verify that dimensions have decreased appropriately
- Ensure no actual content was accidentally cropped

### 5. Quality Assessment
- Ensure the autocrop created appropriate margins (not too tight)
- Verify that all sides were analyzed and cropped if needed
- Confirm the result looks professionally trimmed

### 6. Automatic Export
- The post-task hook will automatically export the result as "autocropped_image.png"

## Verification Strategy

### Verification Approach
The verifier uses **dimensional reduction analysis and border detection** to validate successful autocrop:

### A. Dimension Reduction Verification
- **Size Decrease Detection:** Confirms that output dimensions are smaller than input dimensions
- **Significant Reduction:** Ensures dimensions decreased by meaningful amounts (at least 5% per side with border)
- **Reasonable Bounds:** Validates that the image wasn't over-cropped (retains at least 50% of original area)
- **Content Preservation:** Ensures substantial content remains in the cropped result

### B. Border Removal Analysis
- **Original Border Detection:** Analyzes original image for uniform edge regions
- **Post-crop Edge Analysis:** Examines edges of result image for non-uniform, content-like regions
- **Uniformity Metrics:** Uses standard deviation to distinguish uniform borders from content
- **Border Color Detection:** Identifies if borders were white, black, or other uniform colors

### C. Content Preservation
- **Center Region Comparison:** Verifies that the central content area remains intact
- **Detail Preservation:** Confirms that image detail and structure were maintained
- **No Content Loss:** Ensures no actual subject matter was inadvertently cropped
- **Proper Framing:** Validates that content has appropriate margins, not cropped too tightly

### D. Autocrop Success Indicators
- **All Sides Analyzed:** Confirms autocrop examined and processed all four edges
- **Appropriate Action:** Validates that cropping occurred where borders existed
- **Professional Result:** Ensures the final composition looks intentionally framed
- **Quality Maintenance:** Checks that no degradation or artifacts were introduced

### Verification Checklist
- ✅ **Dimensions Reduced:** Output image is smaller than input (width and/or height decreased)
- ✅ **Borders Removed:** Original uniform border regions successfully eliminated
- ✅ **Content Intact:** Main image content preserved without accidental cropping
- ✅ **Professional Composition:** Result appears properly framed without excessive margins

### Scoring System
- **100%:** Perfect autocrop with appropriate dimension reduction and clean content preservation
- **75-99%:** Good autocrop with minor issues in border detection or sizing
- **50-74%:** Partial autocrop with notable problems but some improvement over original
- **0-49%:** Autocrop failed or resulted in inappropriate cropping

**Pass Threshold:** 75% (requires successful border removal and content preservation)

### Technical Verification Details