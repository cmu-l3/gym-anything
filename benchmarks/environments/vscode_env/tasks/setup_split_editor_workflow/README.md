# VSCode Split-Editor Workflow Task (`setup_split_editor_workflow@1`)

## Overview

This task challenges an agent to set up an efficient multi-file editing workspace by arranging related files in a split-editor layout and making coordinated changes across them. The agent must open three related files (HTML, CSS, JavaScript), arrange them in a visible split view, and make consistent modifications that maintain synchronization between structure, styling, and behavior. This represents a fundamental productivity workflow for frontend developers working with interconnected web technologies.

## Rationale

**Why this task is valuable:**
- **Multi-File Coordination:** Tests ability to manage related files simultaneously rather than switching tabs
- **Spatial Organization:** Requires understanding VSCode's editor group system and split commands
- **Cross-File Consistency:** Changes must maintain logical connections (class names, selectors, event handlers)
- **Common Workflow:** Represents daily practice for web developers editing HTML/CSS/JS together
- **Productivity Pattern:** Efficient developers use splits extensively to maintain context
- **Real-World Messiness:** Files start with inconsistencies that must be harmonized

**Real-world Context:** A frontend developer is implementing a "contact form" component. The HTML structure exists but uses inconsistent class names, the CSS is missing hover states, and the JavaScript validation logic references wrong IDs. They're frustrated switching between tabs and losing their place. They want to see all three files side-by-side, fix the naming inconsistencies, add proper styling, and ensure the JavaScript targets the correct elements—all while maintaining visual context across files.

## Task Description

**Goal:** Arrange three web files in split-editor layout and synchronize changes across HTML/CSS/JS

**Starting State:** 
- Workspace at `/home/ga/workspace/contact_form/` contains three files:
  - `form.html` - Contact form with class name `old-form` and submit button with id `oldSubmit`
  - `styles.css` - Minimal styling, needs form and button selectors
  - `script.js` - JavaScript with event listener targeting `oldSubmit`

**Expected Actions:**

1. **Open all three files** in VSCode (form.html, styles.css, script.js)
2. **Arrange in split layout** - Use "Split Editor Right" or "Split Editor Down" commands to create a multi-pane view with all files visible
3. **Update HTML structure:**
   - Change class from `old-form` to `contact-form`
   - Change button id from `oldSubmit` to `submitBtn`
4. **Add coordinated CSS styling:**
   - Create `.contact-form` selector with basic form styling
   - Add `#submitBtn` selector with button styling (background, padding, border-radius)
   - Include `#submitBtn:hover` state with color change
5. **Synchronize JavaScript:**
   - Update event listener to target `submitBtn` (not `oldSubmit`)
   - Ensure querySelector or getElementById matches the new ID

**Final State:** 
- All three files open and visible in split-editor arrangement
- Consistent naming: `contact-form` class, `submitBtn` id used across all files
- CSS properly styles the form and button with hover state
- JavaScript correctly references updated element IDs

## Skills Required

### A. Interaction Skills
- **File Opening:** Use Ctrl+P quick open or file explorer to open multiple files
- **Split Editor Commands:** Execute "View: Split Editor Right/Down" via Command Palette or shortcuts
- **Editor Navigation:** Switch focus between editor groups (Ctrl+1, Ctrl+2, Ctrl+3)
- **Multi-File Editing:** Make coordinated changes while maintaining context across splits

### B. VSCode Knowledge
- **Editor Groups:** Understand VSCode's editor group system for split layouts
- **Split Commands:** Know how to create side-by-side or stacked editor arrangements
- **Focus Management:** Navigate between editor groups efficiently

### C. Task-Specific Skills
- **Frontend Coordination:** Understand HTML/CSS/JS relationships (classes, IDs, selectors)
- **Naming Consistency:** Recognize when identifiers must match across files
- **CSS Selectors:** Know how to target elements by class (`.`) and ID (`#`)
- **JavaScript DOM Selection:** Use `getElementById`, `querySelector` correctly

## Verification Strategy

### Verification Approach
The verifier uses **multi-file content analysis and cross-file consistency checking**:

### A. File Existence and Content Extraction
- **File Validation:** Confirm all three files exist in expected location
- **Content Parsing:** Read full content of HTML, CSS, and JavaScript files
- **Pattern Matching:** Use regex to extract class names, IDs, selectors, and DOM queries

### B. Cross-File Consistency Validation
- **HTML→CSS Consistency:** 
  - Extract `class="contact-form"` from HTML
  - Verify `.contact-form` selector exists in CSS
  - Extract `id="submitBtn"` from HTML
  - Verify `#submitBtn` selector exists in CSS
  
- **HTML→JavaScript Consistency:**
  - Extract button ID from HTML (`submitBtn`)
  - Verify JavaScript uses `getElementById('submitBtn')` or `querySelector('#submitBtn')`
  - Confirm old identifiers (`oldSubmit`) are removed

### C. Verification Criteria (7 total, need 6+ to pass)

✅ **All Files Present:** HTML, CSS, and JavaScript files exist and have substantial content  
✅ **HTML Updated:** Contains `contact-form` class and `submitBtn` id  
✅ **Old Names Removed:** No longer contains `old-form` or `oldSubmit`  
✅ **CSS Synchronized:** Contains `.contact-form` and `#submitBtn` selectors  
✅ **Hover State Present:** CSS includes `#submitBtn:hover` styling  
✅ **JavaScript Updated:** Targets `submitBtn` (not `oldSubmit`)  
✅ **Cross-File Consistency:** All identifiers match across files, no orphaned references

### Scoring System

- **100%:** Perfect synchronization - all 7 criteria met
- **85%:** Minor issues - 6/7 criteria met (passing threshold)
- **70%:** Significant gaps - 5/7 criteria met
- **50%:** Major problems - 3-4 criteria met
- **0-49%:** Failed - fewer than 3 criteria met

**Pass Threshold:** 85% (requires 6 out of 7 criteria with strong cross-file consistency)

## Technical Implementation

### Files Structure