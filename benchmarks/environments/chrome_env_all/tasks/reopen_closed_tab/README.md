# Chrome Accidentally Closed Tab Recovery Task (`reopen_closed_tab@1`)

## Overview

This task tests an agent's ability to recover accidentally closed browser tabs using Chrome's "Reopen closed tab" feature. The agent must recognize the situation (a needed tab was closed), know that Chrome maintains a history of recently closed tabs, and use the appropriate keyboard shortcut (Ctrl+Shift+T) or menu option to restore it. This represents one of the most common "undo" operations in daily browser use, often performed under time pressure when important work is at stake.

## Task Description

**Goal**: Recover an accidentally closed Wikipedia article tab using Chrome's tab recovery feature.

**Starting State**: Chrome with 3-4 tabs open, where a Wikipedia article about Computer Science was just "accidentally" closed.

**Expected Actions**:
1. Press Ctrl+Shift+T to reopen the most recently closed tab
   - OR -
2. Right-click on tab bar → Select "Reopen closed tab"

**Final State**: The Wikipedia Computer Science article tab is back among the open tabs.

## Real-World Context

**Scenario**: You're a student researching for a term paper with multiple tabs open. While trying to close an advertisement tab, you accidentally press Ctrl+W on your main reference article—a Wikipedia page about computer science that contains the perfect quote you were about to cite. You need to get that tab back immediately before you lose your place.

**User Frustration**: "Oh no! I just closed the wrong tab! That had all the information I needed! How do I get it back??"

**Expected Behavior**: Quickly press Ctrl+Shift+T, which immediately reopens the most recently closed tab, restoring the URL, page state, scroll position, and navigation history.

## Verification Strategy

### Chrome DevTools Protocol (CDP) Based Verification

The verifier uses real-time Chrome DevTools Protocol to:

1. **Retrieve Target URL**: Reads which tab was closed during setup
2. **Query Current Tabs**: Gets all currently open tabs via CDP
3. **Check Presence**: Verifies the target URL is now present
4. **Validate Title**: Ensures the page loaded correctly (not an error page)
5. **Detect Duplicates**: Confirms no duplicate recovery attempts
6. **Count Tabs**: Validates reasonable tab count

### Verification Criteria (4 total, need 3+ to pass)

✅ **Target URL Present**: The closed Wikipedia URL is now in open tabs  
✅ **Valid Title**: Page title contains expected content (not error page)  
✅ **No Duplicates**: Target URL appears exactly once  
✅ **Reasonable Tab Count**: Between 2-10 tabs total (realistic session)  

### Scoring System

- **100%**: All 4 criteria met (perfect recovery)
- **75-99%**: 3/4 criteria met (successful recovery with minor issue)
- **50-74%**: 2/4 criteria met (partial success)
- **0-49%**: <2 criteria met (recovery failed)

**Pass Threshold**: 75% (requires target URL present + 2 other criteria)

## Technical Implementation

### Files

- **task.json**: Task configuration (45s timeout, 5 max steps)
- **setup_task.sh**: Opens Chrome with multiple tabs, closes one programmatically
- **export_result.sh**: Captures final tab state via CDP
- **verifier.py**: Checks if target URL was successfully recovered
- **README.md**: This documentation

### Key Features

1. **Realistic Setup**: Programmatically simulates accidental tab closure
2. **CDP Integration**: Uses Chrome debugging protocol for tab manipulation
3. **URL Tracking**: Records which tab was closed for verification
4. **Flexible Recovery**: Accepts both keyboard shortcut and menu-based recovery
5. **Robust Verification**: Handles URL variations and page load states

### Setup Process

1. Start Chrome with Google homepage
2. Open additional tabs (GitHub, Wikipedia article, Stack Overflow)
3. Use Python + CDP to programmatically close the Wikipedia tab
4. Record closed URL to `/tmp/closed_tab_url.txt`
5. Focus Chrome and wait for agent

### Dependencies

- Chrome with remote debugging (port 9222)
- `curl`, `jq` for CDP queries
- `xdotool`, `wmctrl` for window management
- Python 3 with `requests` library

## Skills Tested

- **Keyboard Shortcut Mastery**: Using Ctrl+Shift+T
- **Alternative Methods**: Right-click menu navigation
- **Mistake Recovery**: Understanding Chrome's undo mechanisms
- **Tab History Awareness**: Knowing Chrome remembers closed tabs
- **Quick Problem Solving**: Rapid recovery under pressure

## Common Failure Modes

1. **Agent doesn't know shortcut**: Tries to manually navigate to history
2. **Wrong shortcut**: Presses Ctrl+T (new tab) or Ctrl+Z (doesn't work)
3. **Over-pressing**: Presses Ctrl+Shift+T multiple times, reopening old tabs
4. **Alternative approach**: Opens history and manually finds URL (slower but valid)
5. **Navigation instead**: Types URL manually rather than using recovery feature

## Alternative Success Paths

- **Primary**: Ctrl+Shift+T keyboard shortcut ⭐
- **Alternative 1**: Right-click on tab bar → "Reopen closed tab"
- **Alternative 2**: Chrome menu → History → Recently closed tabs → Select item
- **Creative**: If bookmarked before closing, could restore from bookmarks

## Learning Outcomes

After completing this task, an agent should understand:

1. Ctrl+Shift+T is the universal "undo close tab" command
2. Chrome maintains a stack of recently closed tabs
3. Tab recovery preserves page state and history
4. Multiple tabs can be recovered sequentially with repeated Ctrl+Shift+T
5. This feature works across Chrome, Firefox, Edge, and other modern browsers

## Comparison to Related Tasks

| Task | Focus | Complexity |
|------|-------|------------|
| `session_restore_crash@1` | Recovery after crash/restart | High |
| `reopen_closed_tab@1` | **Immediate in-session recovery** | **Low** |
| `history_search_recovery@1` | Finding old visited sites | Medium |

**Key Distinction**: This task focuses on the immediate "undo" operation that experienced users perform constantly, not recovery from catastrophic failures or long-term history retrieval.

## Expected Execution Time

- **Novice agent**: 20-30 seconds (exploring menus)
- **Experienced agent**: 2-5 seconds (direct shortcut)
- **Human expert**: <2 seconds (muscle memory)

## Success Indicators

✅ Target Wikipedia URL appears in open tabs  
✅ Page loads correctly with valid title  
✅ No error messages or 404 pages  
✅ Recovery happened quickly (within timeout)  

This task builds essential browser fluency and demonstrates understanding of Chrome's session management and undo mechanisms—critical skills for productive computer use.