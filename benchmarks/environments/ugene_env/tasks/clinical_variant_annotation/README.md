# Clinical Variant Annotation

## Domain Context
Clinical molecular geneticists review sequenced gene data for pathogenic variants before issuing diagnostic reports. Annotation errors in GenBank records — wrong CDS boundaries, missing variant calls, incorrect gene names — can lead to missed diagnoses. This task simulates the real-world workflow of validating and correcting sequence annotations for the BRCA1 breast cancer susceptibility gene.

## Goal
Fix 4 deliberate annotation errors in a patient's BRCA1 GenBank file using UGENE's annotation editing, ORF finding, and sequence analysis tools. Produce a corrected GenBank file and clinical summary report.

## Starting State
- UGENE launched to welcome screen
- Patient file at `~/UGENE_Data/clinical/patient_BRCA1_region.gb` with injected errors
- Empty results directory at `~/UGENE_Data/clinical/results/`

## Success Criteria (100 points total)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Corrected GB file exists | 10 | patient_BRCA1_corrected.gb present and valid GenBank |
| Gene qualifier fixed | 15 | Gene name corrected from BRCA2 to BRCA1 |
| CDS boundaries corrected | 20 | CDS start coordinate adjusted to correct ATG position |
| Missense variant annotated | 15 | variation annotation at C>T position (~1200-1210) |
| Frameshift deletion annotated | 15 | variation annotation at AGT deletion (~1850-1870) |
| ORF annotations present | 10 | ORFs found and annotated with min length 300bp |
| Clinical report complete | 15 | Report lists errors, corrections, and variant classifications |

## Anti-Gaming
- Do-nothing: results/ empty at start → score=0
- Wrong-target: checking for BRCA1 (not BRCA2) ensures gene name was actually fixed
- Coordinate range validation for variant positions
- ORF annotations must be machine-generated (multiple ORFs expected)
