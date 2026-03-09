# insurance_archimate_landscape (`insurance_archimate_landscape@1`)

## Overview
This task evaluates the agent's ability to create an Enterprise Architecture diagram using the **ArchiMate 3.1** modeling language in draw.io Desktop. The agent must interpret a textual architecture description of an insurance claims handling system and model it across three layers (Business, Application, and Technology) using the correct standard ArchiMate notation, shapes, and relationships.

## Rationale
**Why this task is valuable:**
- **Tests Domain-Specific Tooling**: Requires finding and using the specific "ArchiMate 3.0" shape library, not generic rectangles.
- **Tests Architectural Layering**: Evaluates the ability to organize complex systems into Business (Yellow), Application (Blue), and Technology (Green) layers.
- **Tests Relationship Semantics**: Requires distinguishing between "Serving" (used by), "Realization" (implements), and "Assignment" (performs) relationships.
- **High Economic Value**: Enterprise Architects (part of the "Computer Systems Architects" occupation) use these diagrams to manage complex IT transformations in high-GDP industries like Finance and Insurance.

**Real-world Context:** An Enterprise Architect at an insurance company is documenting the "As-Is" state of the Claims Handling capability to prepare for a cloud migration. They need a formal ArchiMate view to show stakeholders how the business process depends on the legacy mainframe system.

## Task Description

**Goal:** Create a 3-layer ArchiMate 3.1 diagram for the "Claims Handling" domain based on the architecture definition provided in `~/Desktop/archisurance_definition.txt`.

**Starting State:** 
- draw.io Desktop is open with a blank canvas.
- The file `~/Desktop/archisurance_definition.txt` exists, containing the list of elements and their relationships.

**Expected Actions:**
1.  Enable the **ArchiMate 3** shape library (via "More Shapes" > "Other" or search).
2.  Create a **Business Layer** (top) with:
    - Actor: "Customer"
    - Business Process: "Submit Claim"
    - Business Object: "Damage Report"
3.  Create an **Application Layer** (middle) with:
    - Application Service: "Claims Intake Service"
    - Application Component: "Policy Administration System"
    - Application Component: "Document Management System"
4.  Create a **Technology Layer** (bottom) with:
    - Node: "Mainframe"
    - System Software: "DB2 Database"
    - Artifact: "Claim PDF"
5.  Draw the correct **Relationships** as specified in the text file (e.g., Customer *assigned to* Submit Claim, Claims Intake Service *serves* Submit Claim, Mainframe *hosts* DB2).
6.  Arrange the shapes hierarchically (Business over App over Tech).
7.  Save the diagram to `~/Desktop/claims_architecture.drawio`.
8.  Export a PNG image to `~/Desktop/claims_architecture.png`.

**Final State:**
- A valid draw.io XML file using `mxgraph.archimate3` shapes.
- A PNG export showing the layered architecture.

## Verification Strategy

### Primary Verification: XML Content Analysis
The verifier parses `~/Desktop/claims_architecture.drawio` to ensure:
1.  **Correct Shape Library**: Checks that shapes have styles starting with `mxgraph.archimate3` (e.g., `mxgraph.archimate3.business.business_actor`). Generic rectangles fail.
2.  **Element Presence**: Verifies the existence of specific elements by label (case-insensitive):
    - "Customer", "Submit Claim", "Damage Report" (Business)
    - "Claims Intake", "Policy Administration", "Document Management" (Application)
    - "Mainframe", "DB2", "Claim PDF" (Technology)
3.  **Color/Layer Compliance**: Checks that Business elements are Yellow-ish (`#ffffcc` or similar), App elements are Blue-ish (`#b5ffff`), and Tech elements are Green-ish (`#c9fcd6`), which is the default for ArchiMate shapes.
4.  **Relationship Count**: Verification of at least 6 connecting edges.

### Secondary Verification: File Artifacts
- Checks for the existence and size of the exported PNG (`claims_architecture.png`).
- Checks that the draw.io file was modified after the task start time.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **File Saved** | 10 | File exists and modified after start |
| **ArchiMate Library Used** | 25 | Shapes use `mxgraph.archimate3` namespace (not generic boxes) |
| **Business Layer** | 15 | Customer, Submit Claim, Damage Report present |
| **App Layer** | 15 | Claims Intake, Policy Admin, DMS present |
| **Tech Layer** | 15 | Mainframe, DB2, Claim PDF present |
| **Relationships** | 10 | At least 6 connections between elements |
| **PNG Export** | 10 | Valid PNG file created |
| **Total** | **100** | |

**Pass Threshold:** 60 points (Must use ArchiMate library to pass).

## Data Source
The architecture definition is based on the **ArchiSurance** case study, the official standard example used by The Open Group to teach ArchiMate 3.1.