# LibreOffice Calc Tasks Suite

This suite provides **7 comprehensive tasks** for training multimodal agents on spreadsheet operations, from basic formulas to data visualization and lookups.

## Tasks Overview

| Task | ID | Difficulty | Skills Tested | Duration |
|------|-----|-----------|---------------|----------|
| [Simple Sum Formula](#1-simple-sum-formula) | `simple_sum_formula@1` | 🟢 Easy | Basic formulas, cell references | ~30 steps |
| [Basic Formulas](#2-basic-formulas) | `basic_formulas@1` | 🟢 Easy | Data entry, arithmetic formulas | ~10 steps |
| [CSV Import](#3-csv-import) | `csv_import@1` | 🟢 Easy | File import, data formatting | ~10 steps |
| [Sort Data](#4-sort-data) | `sort_data@1` | 🟢 Easy | Data manipulation, sorting | ~20 steps |
| [Create Chart](#5-create-chart) | `create_chart@1` | 🟡 Medium | Chart wizard, data visualization | ~40 steps |
| [Conditional Format](#6-conditional-format) | `conditional_format@1` | 🟡 Medium | Formatting rules, conditions | ~40 steps |
| [VLOOKUP Formula](#7-vlookup-formula) | `vlookup_formula@1` | 🟡 Medium | Advanced formulas, lookups | ~60 steps |

## Skill Progression

### 🟢 Beginner (Easy)
**Foundation Skills**: Basic interface navigation, simple operations

1. **Simple Sum Formula** - Learn formula syntax and cell references
2. **Basic Formulas** - Apply arithmetic formulas (SUM, AVERAGE)
3. **CSV Import** - Import and format external data
4. **Sort Data** - Organize data by sorting columns

### 🟡 Intermediate (Medium)
**Applied Skills**: Multi-step workflows, advanced features

5. **Create Chart** - Understand data visualization basics
6. **Conditional Format** - Apply visual rules based on data
7. **VLOOKUP Formula** - Master lookup functions and multi-sheet references

## Running Tasks

```bash
# Run specific task
python -m gym_anything.cli run libreoffice_calc_env --task simple_sum_formula

# Run all tasks sequentially
python -m gym_anything.cli run libreoffice_calc_env --all-tasks

# Validate task configuration
python -m gym_anything.cli validate libreoffice_calc_env --task simple_sum_formula
```

## Task Details

### 1. Simple Sum Formula
**Objective**: Add a SUM formula to calculate the total of numbers in a column

**Skills**: 
- Formula syntax (`=SUM(range)`)
- Cell range references (`A1:A10`)
- Result verification

**Success Criteria**:
- Correct formula in specified cell
- Accurate calculated result
- Proper cell references

### 2. Basic Formulas
**Objective**: Enter data and apply basic arithmetic formulas

**Skills**:
- Data entry
- SUM and AVERAGE functions
- Cell references
- Formula verification

**Success Criteria**:
- Values entered correctly
- Formulas calculated correctly
- Results match expected values

### 3. CSV Import
**Objective**: Import CSV data and format columns appropriately

**Skills**:
- File import operations
- Column formatting
- Data types (currency, dates)
- Data validation

**Success Criteria**:
- Data imported correctly
- Formats applied
- No data loss

### 4. Sort Data
**Objective**: Sort dataset by Score column in ascending order

**Skills**:
- Data menu operations
- Sorting by column
- Data integrity maintenance
- Sort verification

**Success Criteria**:
- Data correctly sorted
- Name-score pairs maintained
- No data loss

### 5. Create Chart
**Objective**: Generate a bar chart from sales data

**Skills**:
- Chart wizard navigation
- Data range selection
- Chart type selection
- Chart positioning

**Success Criteria**:
- Chart exists in sheet
- Correct data range
- Sales data preserved

### 6. Conditional Format
**Objective**: Apply formatting rules to highlight scores

**Skills**:
- Format menu navigation
- Condition rule creation
- Color/style selection
- Range application

**Success Criteria**:
- File saved in ODS format
- Student data preserved
- Formatting applied

### 7. VLOOKUP Formula
**Objective**: Use VLOOKUP to match order data with product information

**Skills**:
- VLOOKUP syntax
- Multi-sheet references
- Lookup table structure
- Formula verification

**Success Criteria**:
- VLOOKUP formulas correct
- Results match expected
- Lookups reference correct sheet

## Verification Strategy

All tasks use **deterministic verification** via file parsing:

1. **File Extraction**: Copy result file from container to host
2. **Format Parsing**: Parse ODS/XLSX using `odfpy`/`openpyxl`
3. **Content Verification**: Check cells, formulas, charts, formatting
4. **Scoring**: 4-criteria evaluation with 75% pass threshold

### Common Verification Checks
- ✅ Cell values match expected
- ✅ Formulas syntactically correct
- ✅ Charts/pivot tables exist
- ✅ Formatting rules applied

## Assets

Each task includes CSV files or templates in `assets/` directory:
- Pre-populated data for consistency
- Realistic datasets (sales, employees, budgets)
- Proper headers and structure

## Tips for Success

1. **Wait for Calc to Load**: LibreOffice takes 3-5s to start
2. **Use Keyboard Shortcuts**: Faster than mouse navigation
3. **Save Frequently**: Ctrl+S to avoid data loss
4. **Check Results**: Verify calculations before export
5. **Format Consistently**: Use proper number formats

## Troubleshooting

**Task Setup Fails**
- Check CSV files exist in assets/
- Verify Calc installation
- Check file permissions

**Verification Fails**
- Ensure file saved in correct format (ODS preferred)
- Check formula syntax matches LibreOffice format
- Verify cell references are absolute/relative as needed

**Calc Doesn't Start**
- Check X11 display running
- Verify user permissions
- Check logs in /tmp/calc_ga.log
