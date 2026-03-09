# Personality EFA Task (jamovi_env)

## Overview
Exploratory Factor Analysis (EFA) on a 25-item Big Five personality inventory using jamovi. The agent must configure the EFA with 5 factors, oblimin rotation, and assumption tests (KMO and Bartlett's), then save the analysis.

## Dataset
**BFI25.csv** (Revelle, 2010) -- ~2,200 participants from the Big Five Inventory.

| Column    | Description                                   | Type       |
|-----------|-----------------------------------------------|------------|
| A1--A5    | Agreeableness items                           | Integer 1-6|
| C1--C5    | Conscientiousness items                       | Integer 1-6|
| E1--E5    | Extraversion items                            | Integer 1-6|
| N1--N5    | Neuroticism items                             | Integer 1-6|
| O1--O5    | Openness items                                | Integer 1-6|
| gender    | 1 = Male, 2 = Female                          | Integer    |
| age       | Participant age                               | Integer    |

All 25 personality items are rated on a 1-6 Likert scale (1 = Very Inaccurate, 6 = Very Accurate).

**Source**: `psych` R package bfi dataset (Revelle, 2010), extracted via `extract_bfi25.py` during `install_jamovi.sh`.
**Path in VM**: `/home/ga/Documents/Jamovi/BFI25.csv`

## Task Requirements
The agent must perform an Exploratory Factor Analysis in jamovi:

### 1. Exploratory Factor Analysis (Factor > Exploratory Factor Analysis)
- **Variables**: All 25 personality items (A1-A5, C1-C5, E1-E5, N1-N5, O1-O5)
- **Exclude**: gender and age (these are demographic variables, not personality items)
- **Number of factors**: 5 (matching the Big Five theoretical structure)
- **Rotation**: Oblimin (oblique rotation -- personality factors are expected to be correlated)
- **Assumption tests**: Enable KMO measure of sampling adequacy and Bartlett's test of sphericity

### 2. Save
- Save the file as: `/home/ga/Documents/Jamovi/BFI_FactorAnalysis.omv`

## Ground Truth (Expected Results)
Based on the BFI-25 dataset (~2,200 participants):

### KMO and Bartlett's Test
- **KMO**: Expected ~ 0.85 (meritorious sampling adequacy)
- **Bartlett's test**: Expected to be highly significant (p < 0.001), indicating the correlation matrix is not an identity matrix

### Factor Structure
With 5 factors and oblimin rotation, the expected pattern approximately maps to the Big Five:
- **Factor 1**: N1-N5 (Neuroticism items load together)
- **Factor 2**: E1-E5 (Extraversion items load together)
- **Factor 3**: C1-C5 (Conscientiousness items load together)
- **Factor 4**: A1-A5 (Agreeableness items load together)
- **Factor 5**: O1-O5 (Openness items load together)

Note: Some items may cross-load or load weakly; the exact factor order depends on variance explained.

## Verification Strategy
The verifier uses a two-stage approach:

1. **export_result.sh** (post_task hook): Extracts the .omv file (ZIP archive), parses the internal `index.html` for EFA-related keywords, and writes a structured JSON to `/tmp/personality_efa_result.json`.

2. **verifier.py**: Multi-criterion scoring (100 points total):
   - File saved at the correct path (15 pts)
   - Valid .omv structure (ZIP with expected contents) (10 pts)
   - EFA analysis present (20 pts)
   - Correct number of factors (5) (15 pts)
   - Oblimin rotation used (15 pts)
   - KMO and Bartlett's test present (15 pts)
   - Factor loadings show personality items, not demographics (10 pts)

   Pass threshold: 70 points

## Difficulty: Hard
- Description says WHAT to do but NOT which menus/buttons to click
- Requires navigating the Factor module (may need installing the jmv module first)
- Must configure number of factors, rotation method, and assumption tests
- Must correctly select only personality items (exclude gender and age)
- Must save all analyses into a single .omv file
- Agent must discover the correct menu paths independently

## jamovi .omv File Format
The .omv format is a ZIP archive containing:
- `index.html` -- rendered analysis output (HTML tables and text)
- `meta` -- metadata about the file
- `data.bin` / `strings.bin` -- binary data storage
- `xdata.json` -- column metadata
- Various analysis result files

The verifier parses `index.html` for the presence of analysis keywords rather than structured JSON options (unlike JASP's analyses.json approach).
