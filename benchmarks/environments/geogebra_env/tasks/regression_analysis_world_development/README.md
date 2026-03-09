# Task: Regression Analysis — World Development Data

## Overview

**Difficulty**: Hard
**Occupation**: Secondary School Teacher (AP Statistics)
**Timeout**: 600 seconds, 70 max steps

An AP Statistics teacher needs to create an interactive regression analysis lesson using real-world data from the United Nations Human Development Report 2021-22. This is a core AP Statistics curriculum topic (inference for regression, comparing models). The real data makes this professionally authentic — these are the exact figures used in international development policy discussions.

## What Makes This Hard

The agent must:
1. **Find and read the pre-staged CSV file** at `~/Documents/GeoGebra/data/world_development.csv`
2. **Enter data into GeoGebra** — either through the Spreadsheet view (View > Spreadsheet) or directly in the input bar as a list of points
3. **Create a scatter plot** by selecting the data and using Statistics > Create List of Points or equivalent
4. **Use GeoGebra's FitLine command** — not the basic line tool; `FitLine(list)` performs least-squares linear regression
5. **Use FitLog** for the logarithmic model — requires knowing that GeoGebra has this command and its correct syntax
6. **Add text annotations** with the regression equations

The FitLine and FitLog commands are not obvious in the GUI — the agent must know to use the input bar or search through the Tools menu.

## Goal (End State)

A file `world_regression.ggb` in `~/Documents/GeoGebra/projects/` containing:
- All 15 UN HDR data points as a scatter plot
- A FitLine regression line
- A FitLog (or similar non-linear) regression curve
- Text annotations with regression equations

## Real Data Source

**United Nations Development Programme — Human Development Report 2021-22**
URL: https://hdr.undp.org/content/human-development-report-2021-22
Table 1: Human Development Index and its components

| Country | GNI per capita (PPP $) | Life Expectancy (years) |
|---------|------------------------|------------------------|
| Norway | 66,494 | 83.2 |
| Switzerland | 66,933 | 83.8 |
| United States | 64,765 | 76.1 |
| Germany | 54,534 | 80.6 |
| United Kingdom | 45,225 | 80.7 |
| Japan | 42,274 | 84.3 |
| South Korea | 44,501 | 83.0 |
| Spain | 38,661 | 83.3 |
| Turkey | 27,701 | 77.7 |
| Brazil | 13,628 | 75.0 |
| China | 17,504 | 78.2 |
| Mexico | 17,628 | 70.2 |
| India | 6,590 | 67.2 |
| Nigeria | 5,026 | 52.7 |
| Ethiopia | 2,206 | 66.6 |

Expected linear regression: positive slope (~0.0002 yrs/$ GDP), indicating higher income → longer life
Expected logarithmic fit: noticeably better (r² ~0.85 vs ~0.75 for linear), showing diminishing returns

## Verification Criteria (100 points total)

| Criterion | Points | How Checked |
|-----------|--------|-------------|
| File created during task | 20 | File exists AND mtime ≥ task start |
| Sufficient data entered (≥10 pts or 1 list) | 20 | Count of point/list elements in XML |
| FitLine (linear regression) present | 20 | `<command name="FitLine">` in geogebra.xml |
| FitLog or other nonlinear regression | 20 | `<command name="FitLog/FitExp/etc.">` |
| Text annotation present | 20 | `<element type="text">` in XML |

**Pass threshold**: 70 points

**Gate**: FitLine must be present for score to reach pass threshold (prevents scatter-only submissions)

## GeoGebra Commands Used

```
list1 = {(66494,83.2), (66933,83.8), ..., (2206,66.6)}    # create data list
FitLine(list1)                                              # linear regression
FitLog(list1)                                               # logarithmic regression
```
