# Backyard Habitat Wildlife Logger Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, VLOOKUP/INDEX-MATCH, date standardization, conditional logic, data validation  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Clean up and standardize inconsistent wildlife observation data collected by a citizen scientist. The backyard naturalist has been manually logging bird and mammal sightings over several months using informal notation, abbreviations, and inconsistent date formats. You must standardize species names, convert dates to uniform format, flag unusual/suspicious entries, and prepare the data for submission to a regional biodiversity monitoring program.

## Task Description

The agent must:
1. Open a spreadsheet with two sheets: "Observations" (messy raw data) and "Species_Reference" (lookup table)
2. Create helper columns for standardized data:
   - Standard_Species (using VLOOKUP/INDEX-MATCH)
   - Standard_Date (converting various date formats)
   - Plausibility_Flag (identifying suspicious entries)
3. Use the Species_Reference sheet to standardize informal species names
4. Convert various date formats to uniform YYYY-MM-DD format
5. Flag entries with implausible counts (exceeding Max_Expected from reference table)
6. Ensure all original observations are preserved
7. Save the cleaned file

## Raw Data Issues

The "Observations" sheet contains:
- **Mixed date formats**: "5/12/23", "May 12 2023", "05-13-2023"
- **Informal species names**: "cardinal", "chickadee", "rabbit" (not standardized)
- **Potential count errors**: Some counts may be implausible (e.g., 50 deer)
- **Inconsistent capitalization**: "Blue Jay" vs "blue jay"

## Species Reference Table

The "Species_Reference" sheet provides:
- Common_Name (informal)
- Standardized_Name (official)
- Scientific_Name
- Max_Expected_Count (plausibility threshold)
- Rarity (Common/Uncommon)

## Expected Actions

### Step 1: Understand the Data
- Examine the Observations sheet (raw data)
- Review the Species_Reference sheet (lookup table)
- Identify data quality issues

### Step 2: Add Helper Columns
Add these columns to the Observations sheet (after existing columns):
- **Standard_Species**: Standardized species name from lookup
- **Standard_Date**: Converted date in uniform format
- **Plausibility_Flag**: "CHECK" if count exceeds Max_Expected, "OK" otherwise

### Step 3: Standardize Species Names
Use VLOOKUP or INDEX-MATCH: