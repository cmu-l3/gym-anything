# Aquarium Water Chemistry Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Formulas (AVERAGE, COUNTIF), Conditional Formatting, Data Analysis  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze aquarium water chemistry data logged over two weeks. Calculate average parameter levels, apply conditional formatting to highlight dangerous readings, count threshold violations, and identify the primary water quality issue. This simulates real-world diagnostic workflows for aquarium hobbyists and aquatic researchers.

## Task Description

The agent must:
1. Review 14 days of water chemistry readings (pH, Ammonia, Nitrite, Nitrate)
2. Calculate average values for each parameter using AVERAGE() function
3. Apply conditional formatting to highlight toxic/dangerous readings:
   - Ammonia >0.25 ppm (red/orange)
   - Nitrite >0.5 ppm (red/orange)
   - Nitrate >40 ppm (yellow/warning)
   - pH outside 6.5-7.5 range (light red)
4. Count threshold violations using COUNTIF() formulas
5. Identify and document the primary water quality problem
6. Save the analyzed spreadsheet

## Starting State

- LibreOffice Calc opens with 14 days of water chemistry data
- Columns: Date, pH, Ammonia (ppm), Nitrite (ppm), Nitrate (ppm)
- Values represent realistic aquarium readings with some problematic levels

## Data Structure

| Date       | pH  | Ammonia(ppm) | Nitrite(ppm) | Nitrate(ppm) |
|------------|-----|--------------|--------------|--------------|
| 2024-01-01 | 7.2 | 0.15         | 0.25         | 35           |
| 2024-01-02 | 7.1 | 0.30         | 0.50         | 38           |
| ...        | ... | ...          | ...          | ...          |

## Safe Parameter Ranges

- **pH:** 6.5-7.5 (most freshwater fish)
- **Ammonia:** 0.0 ppm (toxic at >0.25 ppm)
- **Nitrite:** 0.0 ppm (toxic at >0.5 ppm)
- **Nitrate:** <20 ppm (concerning at >40 ppm)

## Expected Analysis Output

Create a summary section with:
- Average values for each parameter
- Threshold violation counts
- Primary problem identification

Example: