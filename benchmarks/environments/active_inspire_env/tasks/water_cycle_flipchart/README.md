# Task: water_cycle_flipchart

## Overview

A 5th grade science teacher needs a lesson flipchart on the water cycle. This task requires creating a 3-page ActivInspire flipchart with an introductory page naming the three water cycle stages, a visual diagram page using shapes and text labels, and an assessment page with questions. This reflects how science teachers use ActivInspire for concept introduction with visual modeling.

## Domain Context

Science teachers routinely create diagram-based flipcharts in ActivInspire to display and annotate scientific processes. The water cycle is a core 5th grade earth science topic, and a well-structured lesson includes: (1) introducing the concept and vocabulary, (2) a visual model for class discussion, and (3) a formative assessment to check understanding.

## Goal

Create a 3-page flipchart saved as `/home/ga/Documents/Flipcharts/water_cycle_lesson.flipchart` with:

- **Page 1 — Introduction**: Title "The Water Cycle" with subtitle text naming all three stages: Evaporation, Condensation, Precipitation
- **Page 2 — Visual Diagram**: At least 3 shapes representing the cycle stages, each with a text label identifying the stage name
- **Page 3 — Quick Check**: Title "Quick Check" with at least 2 written questions for students

## Starting State

ActivInspire is running with a blank or default flipchart open. No existing file named water_cycle_lesson.flipchart in the Documents/Flipcharts directory.

## Agent Workflow

The agent must:

1. Create a 3-page flipchart using ActivInspire's page management
2. Page 1: Add title and stage names using the text tool
3. Page 2: Use the shape tool to draw at least 3 shapes representing water cycle stages, then add text labels identifying each stage
4. Page 3: Add "Quick Check" title and write assessment questions
5. Save to the specified path

## Success Criteria (100 points total, pass at 70)

| Criterion | Points | Description |
|-----------|--------|-------------|
| File exists + valid format | 20 | File at expected path, valid flipchart ZIP/XML format |
| Page count = 3 | 15 | Flipchart has exactly 3 pages |
| Title present | 10 | "Water Cycle" text found in XML |
| Evaporation present | 15 | "Evaporation" text found in XML |
| Condensation + Precipitation | 15 | Both "Condensation" and "Precipitation" text found |
| Shapes ≥ 3 | 15 | At least 3 shape elements found across page XMLs |
| Quick Check present | 10 | "Quick Check" or "Quick" text found on page 3 |

## Verification Approach

1. **File validation**: Confirmed ZIP/XML flipchart format at exact path
2. **Page count**: Count page XML files in ZIP
3. **Text content**: Search all page XMLs for required vocabulary terms
4. **Shape count**: Count shape elements (AsShape, AsRectangle, AsCircle, etc.) across all pages
5. **Timestamp check**: File must be newer than task start time

## Anti-Gaming

- Timestamp validation prevents using pre-existing files
- Multiple distinct text terms required on different pages
- Shape count requirement forces actual diagram creation (not just text)
- Page count = 3 means agent must navigate multi-page creation
