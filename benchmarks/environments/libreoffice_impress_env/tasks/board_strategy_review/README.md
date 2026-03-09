# Task: Board Strategy Review Presentation

## Overview

**Occupation**: General and Operations Managers
**Difficulty**: very_hard
**Domain**: Corporate Strategy / Board Reporting
**Data Source**: IMF World Economic Outlook October 2023 (real GDP projections)

## Background

General Managers prepare annual strategic review presentations for their Board of Directors. A board deck must contextualize macroeconomic conditions, communicate strategic priorities visually, provide financial performance data, and include presenter notes for the speaking executive. This task tests the ability to build a comprehensive, multi-section board presentation from a minimal stub using real macroeconomic data.

## Starting State

- **Draft file**: `/home/ga/Documents/Presentations/board_strategy_2024.odp` — 5-slide stub (title, macro context placeholder, strategic priorities placeholder, financial snapshot, year ahead)
- **Data file**: `/home/ga/Documents/Presentations/world_economic_data.csv` — IMF WEO October 2023 GDP growth projections for 15 regions/countries (2020-2024 actual and forecast)

## Goal / End State

The completed deck at `/home/ga/Documents/Presentations/board_strategy_2024.odp` must:
1. Contain **at least 12 slides** covering strategy, market context, financial performance, and priorities
2. Include **at least 3 embedded charts** (including visualization of economic data)
3. Have **at least one strategy/priority diagram** — a slide with 6 or more shapes representing strategic pillars or priorities
4. Have **speaker notes on every slide** (at least 12 slides with notes)
5. Be **exported as PPTX** to `/home/ga/Documents/Presentations/board_strategy_2024.pptx` for distribution

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Slide count >= 12 | 25 | Required |
| Charts >= 3 | 30 | Required |
| One slide has >= 6 shapes (strategy diagram) | 20 | Required |
| Notes on >= 12 slides (every slide) | 15 | Required |
| PPTX export exists | 10 | Optional |
| **Pass threshold** | **65** | — |

## Verification Strategy

1. **ODP existence**: Fail immediately if missing
2. **Slide count**: Count `<draw:page>` elements in content.xml
3. **Charts**: Count `Object N/content.xml` files containing `chart:chart` in ZIP
4. **Diagram**: Count shape tags per slide (excluding notes section); require >= 6 on best slide
5. **Notes**: Count `<presentation:notes>` elements with >25 non-tag chars
6. **PPTX**: Copy file, verify existence + size > 5KB

## Economic Data Reference

The `world_economic_data.csv` contains real IMF WEO October 2023 GDP growth projections (%) for:
- Global aggregate, Advanced Economies, G7 countries (US, EU, Japan, UK, Canada)
- Major emerging markets (China, India, Brazil, Russia)
- Regional aggregates (MENA, Sub-Saharan Africa, Latin America)

## Why This Is Hard

- Requires creating 7 new slides with substantive board-level content
- Creating a strategy diagram requires placing 6+ shapes and arranging them meaningfully
- Adding 3 charts requires inserting and configuring data three separate times
- Notes on EVERY slide (12+) demands systematic notes view usage
- PPTX export requires File > Save As with format selection
- All content must be coherent and professional
