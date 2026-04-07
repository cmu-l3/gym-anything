# technical_manual_structuring

## Overview
Transform raw, unstructured technical documentation into a professionally structured technical manual with heading hierarchy, formatted tables, monospace code examples, and table of contents.

## Domain Context
- **Occupation**: Technical Writer / Computer Systems Analyst
- **Industry**: IT systems and network infrastructure
- **Workflow**: Technical writers frequently receive raw documentation dumps from engineering teams and must organize them into structured, professional manuals following industry documentation standards.

## Task Design Pattern
**Multi-deliverable Complex**: The agent must create multiple distinct formatting elements (heading hierarchy, tables, monospace formatting, TOC, title page) from completely unstructured raw text. No formatting spec is provided — the agent must use professional judgment about technical manual conventions.

## Goal
Transform the raw unstructured NetWatch Pro v3.2 documentation into a professional technical manual with proper heading hierarchy, formatted tables, monospace code examples, table of contents, and consistent page layout.

## Starting State
- Document: `/home/ga/Documents/netwatch_manual.odt` — complete technical manual content for a network monitoring system, all as plain paragraphs with no formatting whatsoever
- Calligra Words is open with the document loaded
- No formatting specification provided — agent must apply professional judgment

## Content Structure (all currently plain paragraphs)
- Title page elements (product name, version, company)
- 8 main sections: Introduction, System Requirements, Installation, Configuration, Command Reference, Troubleshooting, API Reference, Appendix
- 10 subsections across sections
- Tabular data embedded as text: hardware requirements, configuration parameters, error codes
- CLI commands embedded as plain text: `netwatch --discover`, `nw-config --set`, etc.

## Success Criteria
1. At least 6/8 H1 section headings
2. At least 6/10 H2 subsection headings
3. At least 2 formatted tables (from tabular text data)
4. At least 2/4 command examples in monospace font
5. Table of Contents present
6. Title formatted (bold, >=14pt)
7. Body text justified (>=2/3 samples)
8. Content preservation (>=6/8 keywords)
9. Page layout defined (margins set)
10. VLM visual verification

Pass threshold: 70%

## Verification Strategy
ODF XML parsing. Checks heading styles, table elements, font families (monospace detection), TOC presence, title formatting, paragraph alignment, page layout properties, and content preservation.

## Data Sources
- **Document content**: Technical manual content for a fictional but realistic network monitoring system (NetWatch Pro v3.2). Structure and terminology follow real network monitoring tool documentation conventions (SNMP, ICMP, REST API, error codes).
- **Format**: No external formatting spec — agent must apply industry-standard technical manual conventions.

## Difficulty: very_hard
- Agent must impose structure on completely unstructured content
- Must make judgment calls about what should be headings, tables, lists, code blocks
- Must create multiple distinct formatting elements (6+ types)
- No formatting specification provided — must apply professional knowledge
- 10 independent verification criteria
- Most demanding task in the suite: requires both understanding document semantics AND technical manual formatting conventions
