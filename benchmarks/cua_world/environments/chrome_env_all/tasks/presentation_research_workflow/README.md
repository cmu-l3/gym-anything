# Chrome Multi-Source Presentation Research Task (`presentation_research_workflow@1`)

## Overview

This task simulates a realistic workflow where a user is preparing presentation materials by researching across multiple sources. The agent must navigate to different websites, organize them with bookmarks, and download a key image resource - representing the common challenge of coordinating information from diverse sources without losing track of the workflow.

## Task Description

**Scenario**: You're preparing a presentation on "Global Climate Trends" for tomorrow. You need to quickly gather sources from multiple websites, organize them for easy reference, and download a key infographic.

**Starting State**: Chrome browser with a resource page displaying a climate infographic

**Required Actions**:

1. **Navigate to Research Sources** (open each in a new tab):
   - `https://data.worldbank.org` (World Bank climate data)
   - `https://scholar.google.com` (Academic research)
   - `https://www.bbc.com/news` (Current news coverage)

2. **Organize Bookmarks**:
   - Create a new folder in the bookmark bar named: **"Climate Presentation"**
   - Bookmark each of the three research sources into this folder

3. **Download Image Resource**:
   - Right-click on the climate infographic shown on the starting page
   - Select "Save image as..."
   - Save as: **climate_infographic.png**

**Final State**: 
- Bookmark bar contains folder "Climate Presentation" with 3 bookmarked URLs
- Downloads folder contains climate_infographic.png

## Skills Tested

### A. Multi-Tab Management
- Opening new tabs (Ctrl+T)
- Switching between tabs
- Maintaining multiple information sources simultaneously

### B. URL Navigation
- Using address bar (Ctrl+L)
- Typing URLs accurately
- Waiting for pages to load

### C. Bookmark Organization
- Creating bookmark folders
- Organizing bookmarks hierarchically
- Understanding bookmark bar structure

### D. Download Management
- Right-click context menus
- "Save image as..." functionality
- File naming and saving

### E. Workflow Coordination
- Multi-step task sequencing
- Maintaining context across actions
- Organizing information systematically

## Verification Strategy

### Multi-Criteria Verification (5 criteria)

The verifier checks:

1. **✓ Bookmark Folder Created** (20 points)
   - Folder named "Climate Presentation" exists in bookmark bar
   - Flexible matching: accepts variations containing "climate" and "presentation"

2. **✓ Three Bookmarks Added** (39 points total, 13 each)
   - World Bank (`worldbank.org`) bookmark present
   - Google Scholar (`scholar.google.com`) bookmark present
   - BBC News (`bbc.com`) bookmark present

3. **✓ Image Downloaded** (30 points)
   - File `climate_infographic.png` exists in Downloads folder
   - File size >10KB (validates it's not corrupted)

4. **✓ Browsing History Verification** (9 points, optional bonus)
   - History shows visits to all three research URLs
   - 3 points per site visited

### Scoring System

- **100%**: Perfect execution (folder + 3 bookmarks + image + history verified)
- **90-99%**: Excellent (4/4 main criteria met)
- **75-89%**: Good (3/4 main criteria met) - **PASSING**
- **60-74%**: Partial (2/4 criteria met) - **FAILING**
- **<60%**: Insufficient (0-1 criteria met)

**Pass Threshold**: 75% (requires bookmark folder + at least 2 bookmarks + image, or equivalent)

### Verification Details
