# VSCode Code Archaeology Task (`trace_function_history@1`)

## Overview

This task challenges an agent to investigate the evolution of a specific function in a codebase by leveraging VSCode's Git integration features. The agent must use git blame, view file history, compare different versions, and trace when problematic behavior was introduced. This represents a critical debugging skill—understanding *why* code is the way it is by examining its historical context and evolution over time.

## Rationale

**Why this task is valuable:**
- **Historical Investigation:** Tests ability to use VSCode's Git integration for code archaeology
- **Debugging Context:** Represents real-world debugging where understanding "when did this break?" is crucial
- **Multi-tool Workflow:** Combines git blame, file history, diff viewing, and navigation
- **Critical Thinking:** Requires connecting historical changes to current behavior
- **Common Frustration:** Addresses the universal experience of "who wrote this and why?"
- **Documentation Skills:** Involves synthesizing historical findings into actionable insights

**Real-world Context:** A developer joins a team and encounters a validation function that behaves strangely for edge cases. The current implementation is convoluted, with multiple conditional branches that seem contradictory. The function has been modified 8 times over several months by different developers. Before attempting a fix, the developer needs to understand: When did the problematic validation logic get introduced? What was the original intent? Were there related changes in other files? What issue was each modification trying to solve? This "code archaeology" is essential to avoid breaking existing (intentional) behavior while fixing the actual bug.

## Task Description

**Goal:** Investigate the history of a buggy function, identify the commit that introduced problematic behavior, and document findings

**Starting State:** 
- VSCode open with a Python project containing a `src/validators.py` file
- The `validate_email_domain()` function has known edge-case bugs
- Git repository with 8 commits of history

**Expected Actions:**
1. Open `src/validators.py` in VSCode (already open)
2. Navigate to the `validate_email_domain()` function
3. Use Git blame (right-click → "Git: View Line History" or inline blame annotations)
4. View file history to see all commits that touched this function
5. Identify the commit that introduced the problematic `.strip().upper()` logic
6. Use "Compare with Previous" to see what changed in that commit
7. Check the commit message for context about why the change was made
8. Create a `FINDINGS.md` file in `/home/ga/workspace/email_validator/` documenting:
   - The commit hash that introduced the bug
   - The date and author
   - The specific change that caused the issue
   - Why this is problematic
9. Save the findings file

**Final State:** VSCode with a `FINDINGS.md` file containing structured investigation results

## Skills Required

### A. Interaction Skills
- **File Navigation:** Open and navigate to specific functions
- **Git Blame:** Right-click context menu or use inline blame annotations
- **File History:** View commit history for a specific file
- **Diff Viewing:** Compare different versions of files
- **Timeline Navigation:** Use VSCode's Timeline view for file history
- **File Creation:** Create new markdown file for documentation

### B. VSCode Knowledge
- **Git Integration:** Understand VSCode's built-in Git capabilities
- **Source Control Panel:** Navigate the Source Control sidebar
- **Timeline View:** Use the Timeline panel in the Explorer
- **Diff Editor:** Interpret side-by-side or inline diffs
- **Inline Blame:** Enable and read inline git blame annotations
- **Command Palette:** Access git commands via Ctrl+Shift+P

### C. Task-Specific Skills
- **Code Archaeology:** Trace the evolution of code through history
- **Root Cause Analysis:** Identify which change introduced a bug
- **Commit Interpretation:** Understand what changes mean in context
- **Historical Context:** Piece together the "why" behind changes
- **Documentation:** Synthesize findings into clear written form
- **Critical Evaluation:** Distinguish intentional behavior from bugs

## Verification Strategy

### Verification Approach
The verifier uses **file content analysis and git repository inspection** to validate the investigation:

### A. Documentation Existence and Quality
- **File Presence:** Verify `FINDINGS.md` exists in the correct location
- **Content Length:** Ensure documentation is substantive (>150 characters ideal)
- **Structure:** Check for markdown formatting (headers, bold text, etc.)

### B. Commit Identification Accuracy
- **Hash Presence:** Verify a valid git commit hash is documented
- **Correct Commit:** Validate the hash matches the problematic commit
- **Hash Format:** Accept both short (7-char) and full (40-char) hashes

### C. Investigation Completeness
- **Author Information:** Check for developer name or "author" mention
- **Change Description:** Verify description includes relevant keywords (strip, upper, changed, modified)
- **Impact Explanation:** Ensure explanation of why the change is problematic
- **Technical Detail:** Look for specific mentions of the code change

### Verification Checklist
- ✅ **FINDINGS.md Exists:** Documentation file created in correct location
- ✅ **Commit Hash Present:** Contains a valid git commit hash (7-40 hex characters)
- ✅ **Correct Commit:** The hash corresponds to the commit that introduced `.strip().upper()`
- ✅ **Author Documented:** Mentions the developer who made the change
- ✅ **Change Described:** Explains what modification was made (at least 2 relevant keywords)
- ✅ **Impact Explained:** Describes why the change causes problems
- ✅ **Well-Structured:** Uses markdown formatting with clear organization

### Scoring System
- **100%:** All 7 criteria met; correct commit identified with comprehensive documentation
- **85-99%:** Correct commit found with good documentation; minor missing details
- **70-84%:** Correct commit identified but incomplete or poorly structured documentation
- **50-69%:** Wrong commit identified OR correct commit with very incomplete documentation
- **0-49%:** No meaningful investigation results or missing documentation file

**Pass Threshold:** 70% (requires correct commit identification and minimally adequate documentation)

## Expected Solution Example
