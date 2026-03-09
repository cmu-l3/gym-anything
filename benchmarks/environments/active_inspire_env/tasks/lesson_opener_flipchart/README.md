# Task: lesson_opener_flipchart

## Overview

A 7th grade social studies teacher needs a lesson opener flipchart for a unit on the American Revolution. This task requires creating a structured 3-page ActivInspire flipchart that covers a Do Now warm-up, learning objectives, and a vocabulary preview — common elements of a standards-aligned lesson opener in secondary education.

## Domain Context

ActivInspire is used extensively by middle and high school teachers to build interactive front-of-class presentations. A **lesson opener** is a standard pedagogical structure: teachers begin each class with a Do Now (a brief activating question), state the learning objectives, and preview key vocabulary. Creating this in ActivInspire requires using multi-page management, the text tool, and the shape/fill tool across three distinct pages.

## Goal

Create a 3-page flipchart saved as `/home/ga/Documents/Flipcharts/american_revolution_opener.flipchart` with:

- **Page 1 — Do Now**: A warm-up activity page with title "Do Now" and a prompt that references the "American Revolution"
- **Page 2 — Objectives**: A learning objectives page with title containing "Objective" and listing lesson goals
- **Page 3 — Vocabulary**: A vocabulary preview page with title containing "Vocabulary" and four colored rectangle boxes for the terms: Revolution, Colony, Independence, Patriot

## Starting State

ActivInspire is running with a blank or default flipchart open. The Documents/Flipcharts directory is clean — no existing file named american_revolution_opener.flipchart.

## Agent Workflow

The agent must:

1. Use ActivInspire's multi-page creation to build a 3-page document
2. Navigate to each page and add appropriate content using the text tool
3. On page 3, use the shape tool to create 4 colored rectangle boxes containing the vocabulary terms
4. Save the completed flipchart to the specified path

No UI navigation steps are provided — the agent must explore ActivInspire's interface to find the right tools and workflows.

## Success Criteria (100 points total, pass at 70)

| Criterion | Points | Description |
|-----------|--------|-------------|
| File exists + valid format | 20 | File at expected path, valid flipchart ZIP/XML format |
| Page count = 3 | 15 | Flipchart has exactly 3 pages |
| Do Now content present | 15 | "Do Now" text found in flipchart XML |
| Objectives content present | 15 | "Objective" or "Objectives" text found |
| Vocabulary terms present | 25 | At least 3 of: Colony, Independence, Patriot, Revolution |
| Rectangle shapes ≥ 4 | 10 | 4+ rectangles on vocabulary page |

## Verification Approach

1. **File validation**: Confirmed ZIP/XML flipchart format at exact path
2. **Page count**: Count page XML files in ZIP archive
3. **Text content**: Extract and search XML files for required terms
4. **Shape detection**: Count AsRectangle/type="Rectangle" elements across all page XML
5. **Timestamp check**: Verify file was created/modified after task start

## Anti-Gaming

- File timestamp must be ≥ task start time (pre-existing files rejected)
- Page count must be exactly 3 (not 1 with all content crammed in)
- Multiple independent text terms required (cannot pass with just one)
- Shapes must be actual rectangles (not text elements)
