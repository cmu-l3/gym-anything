# Chrome Screenshot Webpage Region Task (`screenshot_webpage_region@1`)

## Overview

This task tests an agent's ability to capture a specific region of a webpage as a screenshot using Chrome's built-in DevTools screenshot functionality. The scenario involves a data analyst preparing a quarterly report who needs to capture a clean screenshot of a specific data visualization (a revenue chart) from an analytics dashboard without manually cropping afterward.

## Rationale

**Why this task is valuable:**
- **Real-world Documentation Workflow:** Capturing web content for reports, presentations, and tutorials is extremely common in professional settings
- **Precision Visual Task:** Requires understanding of viewport positioning and Chrome's screenshot capabilities
- **Multi-tool Orchestration:** Combines webpage navigation, DevTools usage, and file system awareness
- **Context-aware Execution:** Must identify and capture the correct content region
- **Professional Productivity:** Essential skill for technical writers, educators, data analysts, and developers
- **Alternative to Manual Cropping:** Tests ability to capture clean screenshots without post-processing

**Human Context:** A data analyst is preparing a quarterly report and needs to capture a specific data visualization from an internal dashboard. Manual cropping is time-consuming and imprecise. They need Chrome to capture exactly the chart area with proper resolution for inclusion in the report.

## Skills Required

### A. Interaction Skills
- **Webpage Navigation:** Load target URL and wait for page to fully render
- **DevTools Access:** Open Chrome DevTools using F12 keyboard shortcut
- **Command Menu Navigation:** Access DevTools Command Menu using Ctrl+Shift+P
- **Screenshot Command Selection:** Type and select "Capture screenshot" command
- **File System Awareness:** Understand that screenshots save to Downloads folder
- **Viewport Positioning:** Ensure target content is visible before capturing

### B. Chrome Knowledge
- **DevTools Capabilities:** Understand Chrome's built-in screenshot features
- **Screenshot Command:** Know how to access hidden Chrome commands via Command Menu
- **Download Location:** Understand default download directory behavior
- **Rendering Timing:** Wait for page elements to load before capturing
- **Screenshot Types:** Distinguish between full page, visible area, and node-specific captures

### C. Task-Specific Skills
- **Content Identification:** Visually identify the correct region to capture
- **Framing Judgment:** Ensure target content is properly positioned in viewport
- **Quality Assessment:** Confirm screenshot captures the intended content clearly
- **Timing Awareness:** Capture after dynamic content fully loads
- **File Verification:** Understand where to find the saved screenshot

## Task Steps

### 1. Navigate to Target Page
- Chrome opens and navigates to a test analytics dashboard page
- The page displays a Q4 2024 Revenue Chart with distinctive purple gradient
- Wait for page to fully load (all elements render completely)

### 2. Position Viewport
- The chart should be visible in the viewport
- Scroll if necessary to ensure the target content is centered

### 3. Open Chrome DevTools
- Press **F12** to open DevTools panel
- DevTools opens at bottom or side of browser window

### 4. Access Command Menu
- With DevTools open, press **Ctrl+Shift+P** (or **Cmd+Shift+P** on Mac)
- The Command Menu opens showing available commands

### 5. Select Screenshot Command
- Type "**screenshot**" in the Command Menu search
- Available options appear:
  - "Capture full size screenshot" - entire page
  - **"Capture screenshot"** - visible viewport only (use this one)
  - "Capture node screenshot" - specific DOM element
- Press Enter to select "Capture screenshot"

### 6. Screenshot Automatically Saved
- Chrome captures the visible viewport
- Screenshot saves to Downloads folder automatically
- Filename format: `Screenshot YYYY-MM-DD at HH.MM.SS.png`

### 7. Automatic Verification
- The verifier checks Downloads folder for recently created PNG files
- Analyzes the screenshot to verify it contains expected content

## Verification Strategy

### Verification Approach
The verifier uses **multi-layered screenshot analysis** combining file system checks, metadata validation, and content analysis:

### A. File System Validation
- **Screenshot File Detection:** Searches Downloads directory for recently created PNG files matching Chrome's screenshot naming pattern (`Screenshot*.png`)
- **Timestamp Verification:** Confirms screenshot was created during task execution window (after task start, within 3 minutes)
- **File Size Validation:** Ensures screenshot is not empty or corrupted (minimum 5KB, maximum 10MB)
- **Format Integrity:** Verifies PNG file format is valid and readable

### B. Image Metadata Analysis
- **Dimension Verification:** Checks image has reasonable dimensions (400x300 to 3840x2160)
- **Viewport Size:** Validates dimensions are appropriate for a browser viewport screenshot
- **Not Full Page:** Confirms it's a viewport capture, not an entire scrolling page capture
- **Aspect Ratio:** Ensures realistic browser window proportions

### C. Content Analysis
- **Color Distribution:** Analyzes if image contains expected purple/blue gradient colors from the chart
- **Complexity Check:** Verifies image is not blank, solid color, or error page
- **Purple Gradient Detection:** Looks for target gradient colors (#667eea to #764ba2)
- **Pixel Diversity:** Confirms sufficient color variety indicating actual content

### D. Timing and Context
- **Creation Time:** Validates screenshot timestamp is within task execution window
- **Not Pre-existing:** Ensures file wasn't already in Downloads before task started
- **Recent Modification:** Confirms file is genuinely new

### Verification Checklist
- ✅ **Screenshot File Exists:** PNG file found in Downloads with correct naming pattern
- ✅ **Recent Creation:** File created during task execution window
- ✅ **File Valid:** Screenshot is readable, proper size (5KB-10MB)
- ✅ **Dimensions Appropriate:** Image size suitable for viewport screenshot (400x300 to 3840x2160)
- ✅ **Content Match:** Screenshot contains expected purple gradient and color distribution

### Scoring System
- **100%:** All 5 criteria met - perfect screenshot capture with verified content
- **80%:** 4/5 criteria met - good screenshot with minor issues (still passing)
- **60%:** 3/5 criteria met - partial success but significant issues (failing)
- **40%:** 2/5 criteria met - major problems
- **<40%:** 0-1 criteria met - task failed

**Pass Threshold:** 75% (requires at least 4 out of 5 criteria)

### Technical Verification Details