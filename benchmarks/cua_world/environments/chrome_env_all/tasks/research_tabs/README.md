# Chrome Multi-Tab Research Task (`research_tabs@1`)

## Overview

This task tests an agent's ability to use Chrome's tab management features to organize multiple web resources for a research or work session. The agent must open specific URLs in new tabs, maintain them simultaneously, and demonstrate understanding of multi-tab workflows.

## Task Description

**Goal**: Open multiple research tabs (Python documentation, MDN Web Docs, and Stack Overflow) to organize web resources for a research session.

**Starting State**: Chrome with one tab open on Google homepage

**Expected Actions**:
1. Press Ctrl+T to open a new tab
2. Navigate to `https://docs.python.org/3/`
3. Press Ctrl+T to open another new tab
4. Navigate to `https://developer.mozilla.org/en-US/`
5. Press Ctrl+T to open a third new tab
6. Navigate to `https://stackoverflow.com/`

**Final State**: Chrome with 4 tabs open containing:
- Original tab (Google or similar)
- Python documentation
- MDN Web Docs
- Stack Overflow

## Verification Strategy

### Chrome DevTools Protocol (CDP) Based Verification

The verifier uses real-time Chrome DevTools Protocol queries to:

1. **Query All Open Tabs**: Retrieves complete tab list from `http://localhost:9222/json`
2. **Filter Page Tabs**: Excludes background pages, extensions, and service workers
3. **Verify Tab Count**: Ensures exactly 4 tabs are open
4. **Check URLs**: Confirms all three research URLs are present
5. **Validate Titles**: Verifies page titles contain expected keywords
6. **Detect Errors**: Identifies failed page loads or error pages
7. **Check Duplicates**: Ensures no duplicate research URLs

### Verification Criteria (5 total, need 4+ to pass)

✅ **Tab Count**: Exactly 4 tabs open (original + 3 research)  
✅ **URLs Present**: All three URLs detected (Python docs, MDN, Stack Overflow)  
✅ **Titles Valid**: Tab titles contain identifying keywords  
✅ **No Errors**: No error pages or failed loads  
✅ **No Duplicates**: Each research URL appears only once  

### Scoring System

- **100%**: All 5 criteria met (perfect execution)
- **80%**: 4/5 criteria met (minor issue, still passing)
- **60%**: 3/5 criteria met (partial success, failing)
- **40%**: 2/5 criteria met (significant issues)
- **0-20%**: 0-1 criteria met (task failed)

**Pass Threshold**: 75% (requires at least 4 out of 5 criteria)

## Technical Implementation

### Files

- **task.json**: Task configuration (120s timeout, 15 max steps)
- **setup_task.sh**: Initializes Chrome with single tab on Google
- **export_result.sh**: Captures all tab information via CDP
- **verifier.py**: CDP-based multi-criteria verification
- **README.md**: This documentation

### Key Features

1. **CDP Real-time Verification**: Accesses live browser state without file system operations
2. **Flexible URL Matching**: Handles minor URL variations (trailing slashes, query parameters)
3. **Title Content Validation**: Confirms pages actually loaded with correct content
4. **Comprehensive Error Detection**: Identifies failed loads, duplicates, and missing tabs
5. **Detailed Feedback**: Provides specific information about which criteria passed/failed

### Dependencies

- Chrome with remote debugging enabled (port 9222)
- `curl`, `jq` for CDP queries
- `xdotool`, `wmctrl` for window management
- Python 3 with `json` module

## Skills Tested

- **Tab Creation**: Using Ctrl+T keyboard shortcut
- **URL Navigation**: Ctrl+L to access address bar, typing URLs
- **Multi-step Coordination**: Maintaining context across multiple actions
- **Tab Management**: Understanding browser tab system
- **Keyboard Proficiency**: Essential Chrome shortcuts

## Common Failure Modes

1. **Wrong Tab Count**: Agent opens too many/few tabs
2. **Missing URLs**: Agent navigates to wrong websites
3. **Closed Original Tab**: Agent accidentally closes the starting tab
4. **Duplicate Tabs**: Agent opens same URL multiple times
5. **Error Pages**: Pages fail to load (network issues, typos)
6. **Incomplete Loads**: Agent doesn't wait for pages to fully load

## Example Successful Execution
