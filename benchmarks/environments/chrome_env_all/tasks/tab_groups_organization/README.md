# Chrome Tab Groups Organization Task (`tab_groups_organization@1`)

## Overview

This task tests an agent's ability to use Chrome's Tab Groups feature to organize multiple open tabs into logical, color-coded groups with meaningful names. The agent must analyze tab content, determine appropriate groupings, create tab groups, assign colors and names, and organize a working session into a clean, categorized structure.

## Task Description

**Goal**: Organize 12 open tabs into 4 logical tab groups (News, Shopping, Documentation, Social) with appropriate names and colors.

**Starting State**: Chrome with 12 tabs open across 4 categories:
- **News**: BBC, CNN, Reuters (3 tabs)
- **Shopping**: Amazon, eBay, Etsy (3 tabs)  
- **Documentation**: MDN, Python Docs, Stack Overflow (3 tabs)
- **Social**: Twitter, Reddit, LinkedIn (3 tabs)

**Expected Actions**:
1. Identify tabs by category (analyze URLs/titles)
2. Create first tab group by right-clicking a news tab → "Add tab to new group"
3. Name the group "News" and assign a color (e.g., blue)
4. Add remaining news tabs to the "News" group
5. Repeat for "Shopping", "Documentation", and "Social" groups
6. Ensure each group has distinct color and appropriate name
7. Verify all 12 tabs are organized into the 4 groups

**Final State**: Chrome with 12 tabs organized into 4 named, color-coded tab groups

## Verification Strategy

### CDP-Based Tab Verification

Since Chrome's Tab Groups metadata is not directly exposed via CDP in most versions, the verifier uses a **URL-based categorization approach** as a proxy for group membership:

1. **Query All Tabs**: Retrieves complete tab list via CDP (`http://localhost:9222/json`)
2. **Categorize by URL**: Determines expected category for each tab based on domain
3. **Verify Presence**: Ensures all 12 expected tabs exist
4. **Check Counts**: Validates each category has exactly 3 tabs
5. **Detect Issues**: Identifies missing, duplicate, or uncategorized tabs

### Verification Criteria (5 total, need 4+ to pass)

✅ **Total Tab Count**: Exactly 12 tabs present (none closed)  
✅ **All Categorized**: All tabs match expected categories (no strays)  
✅ **Category Counts**: Each category has exactly 3 tabs  
✅ **No Duplicates**: No duplicate URLs within categories  
✅ **Domains Present**: All expected domains are represented  

### Scoring System

- **100%**: All 5 criteria met (perfect organization)
- **80%**: 4/5 criteria met (minor issue, passing)
- **60%**: 3/5 criteria met (partial success, failing)
- **40%**: 2/5 criteria met (significant issues)
- **0-20%**: 0-1 criteria met (task failed)

**Pass Threshold**: 80% (requires at least 4 out of 5 criteria)

## Technical Implementation

### Files

- **task.json**: Task configuration (180s timeout, 25 max steps)
- **setup_task.sh**: Opens 12 tabs across 4 categories
- **export_result.sh**: Captures tab information via CDP
- **verifier.py**: URL-based categorization verification
- **README.md**: This documentation

### Key Features

1. **Realistic Tab Setup**: Opens actual websites across diverse categories
2. **Flexible Verification**: Works without direct tab group API access
3. **Category-Based Validation**: Verifies logical organization even if group metadata unavailable
4. **Comprehensive Feedback**: Detailed per-category analysis
5. **Robust Error Handling**: Multiple fallback paths for data retrieval

### Expected Tab Categories
