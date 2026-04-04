# Environmental Metagenome Primer Design

## Domain Context
Environmental microbiologists designing clade-specific PCR primers for metagenomic surveys must align 16S rRNA reference sequences, identify variable regions that discriminate target from non-target organisms, and use primer design software to generate primers with appropriate thermodynamic properties. This is the standard workflow for developing diagnostic primers for bioremediation monitoring.

## Goal
Align 14 bacterial 16S rRNA sequences using Kalign, identify SRB-specific variable regions, design PCR primers using Primer3, and produce an alignment, primer specifications, and specificity analysis report.

## Starting State
- UGENE launched to welcome screen
- 3 FASTA files in `~/UGENE_Data/environmental/`
- Empty results directory

## Success Criteria (100 points total)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Alignment FASTA file | 12 | srb_alignment.fasta with valid aligned sequences |
| All 14 sequences present | 10 | Alignment contains all target + non-target sequences |
| Primer design file exists | 15 | primer_design.txt with forward and reverse primers |
| Primers have valid sequences | 13 | Primer sequences are valid DNA (ACGT only, 18-25bp) |
| Primers have Tm values | 10 | Tm reported and in 55-65°C range |
| Amplicon size specified | 10 | Product size 200-500bp |
| Specificity report exists | 15 | Report discusses V-region selection and SRB specificity |
| Report has PCR conditions | 15 | Report includes annealing temp and cycle recommendations |

## Anti-Gaming
- Do-nothing: results/ empty → score=0
- Primer validation: must be valid DNA sequences of correct length
- Tm range validation: must be biologically plausible
- Report must mention SRB/sulfate-reducing/Desulfovibrio
