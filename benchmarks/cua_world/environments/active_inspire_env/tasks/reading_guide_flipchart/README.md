# Task: reading_guide_flipchart

## Overview

A 3rd grade language arts teacher needs a reading comprehension guide flipchart for Charlotte's Web by E.B. White. This task requires creating a 4-page ActivInspire flipchart covering the title/book info, comprehension questions, character analysis with labeled boxes, and a theme/message section. This is a standard ELA teacher workflow for building guided reading materials that support class discussion and student note-taking.

## Domain Context

Language arts teachers use ActivInspire to build structured reading guides that students follow during class. For a novel study, the standard structure is: book information page, comprehension questions, character analysis (often using labeled boxes or organizers), and a theme/message reflection. Creating this requires multi-page management, structured text entry, and rectangle shapes for the character analysis organizer.

## Goal

Create a 4-page flipchart saved as `/home/ga/Documents/Flipcharts/charlottes_web_guide.flipchart` with:

- **Page 1 — Title**: "Charlotte's Web" as main title, "By E.B. White" as subtitle, student name/class line
- **Page 2 — Questions**: Title "Comprehension Questions" with at least 3 numbered questions about the story
- **Page 3 — Characters**: Title "Character Analysis" with a labeled rectangle box for each of the three main characters: Wilbur, Charlotte, and Fern
- **Page 4 — Theme**: Title "Theme and Message" with text prompts about the book's theme and lesson

## Starting State

ActivInspire is running with a blank or default flipchart. No existing file named charlottes_web_guide.flipchart in Documents/Flipcharts.

## Agent Workflow

The agent must:

1. Create a 4-page flipchart
2. Add book title information on page 1
3. Write comprehension questions on page 2
4. Draw 3 labeled character boxes (rectangles with character names) on page 3
5. Write theme prompts on page 4
6. Save to the specified path

The character analysis page requires using both the shape tool (rectangles) and the text tool with specific character names — Wilbur, Charlotte, and Fern.

## Success Criteria (100 points total, pass at 70)

| Criterion | Points | Description |
|-----------|--------|-------------|
| File exists + valid format | 15 | File at expected path, valid flipchart ZIP/XML |
| Page count = 4 | 15 | Flipchart has exactly 4 pages |
| "Charlotte" text present | 15 | "Charlotte" found in XML (book title or character) |
| "Wilbur" text present | 15 | "Wilbur" found in XML (main character) |
| "Fern" text present | 10 | "Fern" found in XML (third character) |
| "Comprehension" text present | 10 | "Comprehension" found in XML (page 2 title) |
| Rectangle shapes ≥ 3 | 15 | At least 3 rectangles (character boxes) found |
| "Theme" text present | 5 | "Theme" found in XML (page 4 title) |

## Verification Approach

1. **File validation**: ZIP/XML format at exact path
2. **Page count**: Count page XML files in ZIP
3. **Text content**: Search all page XMLs for character names and structural terms
4. **Rectangle shapes**: Count AsRectangle elements across all page XMLs
5. **Timestamp**: File newer than task start time

## Anti-Gaming

- All three character names required (Wilbur, Charlotte, Fern) — cannot skip character analysis page
- Rectangle count ≥ 3 enforces actual character box creation, not just text
- 4 pages required — agent must build all sections
- Both "Comprehension" and "Theme" required to confirm all sections completed
