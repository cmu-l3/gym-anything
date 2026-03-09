# Chrome Tab Group Organization Task (`tab_group_organize@1`)

## Overview

This task challenges an agent to use Chrome's tab groups feature to organize multiple open tabs into logical, color-coded groups with descriptive names. The agent must create multiple tab groups, assign appropriate colors, give them meaningful names, and drag tabs into their correct groups. This represents a sophisticated tab management workflow commonly used by power users, researchers, developers, and anyone managing complex multi-project browsing sessions.

## Task Description

**Goal**: Organize 15+ pre-opened tabs into at least 3 logical tab groups with meaningful names and distinct colors.

**Starting State**: Chrome with 15+ tabs open across different categories:
- **ML Research** (5 tabs): arxiv, paperswithcode, huggingface, github trending, google scholar
- **Travel Planning** (4 tabs): booking, tripadvisor, kayak, airbnb  
- **Shopping** (3 tabs): amazon, ebay, etsy
- **News** (3 tabs): hacker news, reuters, bbc

**Expected Actions**:
1. Right-click on a tab → Select "Add tab to new group"
2. Click on the colored circle → Name the group (e.g., "ML Research")
3. Select an appropriate color from the palette
4. Repeat for other categories (at least 3 groups total)
5. Right-click other tabs → "Add tab to group" → Select appropriate group
6. Organize all tabs into their logical groups

**Final State**: 
- At least 3 tab groups created
- Each group has a meaningful name (not "Untitled" or "Group 1")
- Each group has a distinct color
- 80%+ of tabs are assigned to groups
- Each group contains 2+ tabs (no single-tab groups)

## Rationale

**Why this task is valuable:**
- **Real-world Pain Point**: Tab overload is one of the most common Chrome user frustrations
- **Modern Feature**: Tests knowledge of relatively recent Chrome features (tab groups added in 2020)
- **Complex Interaction**: Requires sophisticated sequence of right-clicks, dragging, typing, and color selection
- **Organizational Skills**: Tests categorization and information architecture abilities
- **Practical Utility**: Directly applicable to real productivity workflows

## Skills Required

### A. Interaction Skills
- Right-click context menus on tabs
- Drag and drop tab manipulation
- Text input in small UI elements
- Color palette selection
- Group bubble clicking and expansion
- Multi-step workflow coordination

### B. Chrome Knowledge
- Tab groups feature existence and purpose
- "Add tab to new group" vs "Add to existing group"
- Group naming via clicking group circle
- Chrome's 8-color palette (grey, blue, red, yellow, green, pink, purple, cyan)
- Group persistence across sessions
- Tab organization best practices

### C. Task-Specific Skills
- Topic/project identification from URLs
- Semantic color association (e.g., blue for research, green for travel)
- Concise naming conventions
- Information architecture and categorization
- Cognitive grouping of related resources

## Verification Strategy

### Chrome Preferences File Analysis

The verifier uses Chrome's Preferences file which stores tab group metadata in the `tab_groups.saved_tab_groups` section.

### Verification Criteria (5 total, need 3+ to pass at 70%)

✅ **Criterion 1**: At least 3 groups created  
✅ **Criterion 2**: All groups have proper names (non-empty, not "Untitled")  
✅ **Criterion 3**: Groups have distinct colors from Chrome's palette  
✅ **Criterion 4**: High grouping coverage (80%+ of tabs assigned to groups)  
✅ **Criterion 5**: No trivial single-tab groups (each group has 2+ tabs)  

### Scoring System

- **100%**: All 5 criteria met (perfect organization)
- **85-99%**: 4/5 criteria met (excellent work)
- **70-84%**: 3/5 criteria met (acceptable, passing)
- **50-69%**: 2/5 criteria met (insufficient organization)
- **0-49%**: 0-1 criteria met (task failed)

**Pass Threshold**: 70% (requires at least 3 out of 5 criteria)

## Technical Implementation

### Files

- **task.json**: Task configuration (180s timeout, 20 max steps)
- **setup_task.sh**: Opens 15+ tabs across 4 categories
- **export_result.sh**: Closes Chrome gracefully, exports Preferences file
- **verifier.py**: Parses Preferences, validates tab group organization
- **README.md**: This documentation

### Key Features

1. **Preferences File Parsing**: Reads Chrome's JSON preferences for tab group metadata
2. **Multi-criteria Validation**: Checks group count, naming, colors, coverage, sizes
3. **Flexible Path Handling**: Tries multiple Chrome profile locations
4. **Detailed Feedback**: Provides specific information on each group and criterion
5. **Robust Error Handling**: Gracefully handles missing data or malformed preferences

### Chrome Preferences Structure
