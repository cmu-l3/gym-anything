# Jump to Line Number Task

**Difficulty**: 🟢 Easy  
**Skills**: Navigation, keyboard shortcuts, line number awareness  
**Duration**: 30 seconds  
**Steps**: ~10

## Objective

Navigate to a specific line number (line 342) in a Python file using VSCode's "Go to Line" feature, then add a marker comment to confirm correct position.

## Real-World Context

**Scenario**: You're on a Zoom call for a code review session. Your senior engineer says: "Hey, can you check line 342 in main.py? I think there's a potential race condition in that variable assignment." You need to jump to that line immediately to discuss it.

## Expected Workflow

**Method 1 (Recommended)**:
1. Press `Ctrl+G` (Go to Line)
2. Type "342"
3. Press Enter
4. Add comment `# CHECKPOINT` on that line
5. Save file (Ctrl+S)

**Method 2 (Alternative)**:
1. Press `Ctrl+P` (Quick Open)
2. Type `:342` (colon followed by line number)
3. Press Enter
4. Add comment `# CHECKPOINT` on that line
5. Save file (Ctrl+S)

## Verification

Checks for:
1. File contains the marker comment `# CHECKPOINT`
2. Comment appears at line 342 (exact position)
3. Line 342 is non-empty with valid Python syntax
4. File was saved successfully

**Pass Threshold**: 75% (3/4 criteria)

## Skills Tested

- Quick line navigation (Ctrl+G)
- Understanding VSCode keyboard shortcuts
- Line number awareness
- Responding to line references in collaboration