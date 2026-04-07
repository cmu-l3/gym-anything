# Add Reference Hyperlinks to Tasks (`add_task_hyperlinks@1`)

## Overview
This task requires the agent to attach external reference documentation to specific tasks in ProjectLibre using the Hyperlink feature. The agent must locate specific tasks, access the hyperlink properties (via context menu or column), and enter both web URLs and local file paths. Finally, the agent must export the project to MSPDI XML format to persist the metadata.

## Rationale
**Why this task is valuable:**
- **UI Discovery:** Tests the agent's ability to find "secondary" metadata features often hidden in context menus or specific dialog tabs.
- **Data Entry Precision:** Requires handling of structured metadata (Title vs. Address) rather than free-text notes.
- **File System Awareness:** Tests the distinction between web protocols (`https://`) and file system paths (`file:///`) in application inputs.
- **Real-world relevance:** In complex engineering projects, the schedule serves as a central hub linking to blueprints, permits, and Jira tickets.

**Real-world Context:** A Wind Energy Development Manager is preparing the schedule for the "Eagle Ridge Turbine Installation" project. The site team needs immediate access to the latest technical specifications and the environmental compliance permit directly from the Gantt chart on their tablets. You need to link these critical documents to the relevant tasks.

## Task Description

**Goal:** Add specific hyperlinks (titles and addresses) to the "System Architecture Design" and "Security Audit" tasks, then export the project as an XML file.

**Starting State:**
- ProjectLibre is launched with `sample_project.xml` loaded.
- The Gantt chart view is active.

**Expected Actions:**
1. Locate the task **"System Architecture Design"** (Task ID 2).
2. Add a hyperlink to this task with:
   - **Description/Title:** `Design Spec v2`
   - **Address/URL:** `https://internal.corp/specs/sys_arch_v2.pdf`
3. Locate the task **"Security Audit"** (Task ID 11).
4. Add a hyperlink to this task with:
   - **Description/Title:** `EPA Permit`
   - **Address/URL:** `file:///home/ga/Documents/permits/epa_compliance_2025.pdf`
   *(Note: The file does not need to actually exist on disk; just enter the path string.)*
5. Save the project as an **XML file** (Microsoft Project format) to `~/Projects/linked_project.xml`.

**Final State:**
- The file `~/Projects/linked_project.xml` exists.
- The file contains the correct `<Hyperlink>` and `<HyperlinkAddress>` elements for the specified tasks.

## Verification Strategy

### Primary Verification: XML File Parsing
The verifier will parse the exported MSPDI XML file (`~/Projects/linked_project.xml`) to confirm:

1. **File Validity:** The file exists and is valid XML.
2. **Task 2 Link:** The task named "System Architecture Design" contains:
   - `<Hyperlink>` matching "Design Spec v2"
   - `<HyperlinkAddress>` matching "https://internal.corp/specs/sys_arch_v2.pdf"
3. **Task 11 Link:** The task named "Security Audit" contains:
   - `<Hyperlink>` matching "EPA Permit"
   - `<HyperlinkAddress>` matching "file:///home/ga/Documents/permits/epa_compliance_2025.pdf"

### Secondary Verification: VLM Trajectory Analysis
The verifier checks the screenshot history for:
- The "Hyperlink" dialog box being open.
- The "Hyperlink" icon appearing in the Indicator column (often a small globe or chain link icon) next to the modified tasks.
- Usage of the "Save As" dialog to export to XML.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **Export Success** | 20 | Valid MSPDI XML file created at `~/Projects/linked_project.xml`. |
| **Task 2 Title** | 20 | "Design Spec v2" is correctly set as the hyperlink description for Task 2. |
| **Task 2 URL** | 20 | The https URL is correctly set for Task 2. |
| **Task 11 Title** | 20 | "EPA Permit" is correctly set as the hyperlink description for Task 11. |
| **Task 11 Path** | 20 | The file path is correctly set for Task 11. |
| **Total** | **100** | |

**Pass Threshold:** 80 points (Must get file export and at least 3 of 4 data fields correct).