# Forensic STR Profiling

## Domain Context
Forensic DNA analysts use Short Tandem Repeat (STR) profiling to generate genetic fingerprints from crime scene evidence. The FBI's CODIS system uses 20+ STR loci; this task focuses on three core loci (D13S317, vWA, TH01). Each locus contains a region of tandemly repeated 4-base motifs whose repeat count varies between individuals. Determining the repeat count from raw sequence data and annotating the STR regions is a fundamental forensic genetics workflow.

## Goal
Using UGENE's sequence analysis tools, the agent must:
- Identify tandem repeat motifs in three CODIS STR reference loci
- Annotate the core repeat regions with structured annotations
- Align evidence allele sequences against reference loci using Smith-Waterman
- Generate annotated GenBank files and a summary report

## Starting State
- UGENE is launched and ready (welcome screen or blank workspace)
- Three GenBank files in `~/UGENE_Data/forensic/`: D13S317_locus.gb, vWA_locus.gb, TH01_locus.gb
- One FASTA file: `evidence_sample_alleles.fasta` with 3 allele sequences (one per locus)
- Results directory `~/UGENE_Data/forensic/results/` exists but is empty

## Agent Workflow (not provided to agent)
1. Open each GenBank file in UGENE
2. Use Analyze > Find Tandem Repeats on each sequence
3. Create STR_core_repeat annotations in forensic_markers group
4. Open evidence FASTA, run Smith-Waterman against each locus
5. Save annotated files to results/
6. Write summary report

## Success Criteria (100 points total)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Annotated GB files exist | 15 | All 3 annotated GenBank files present in results/ |
| GenBank format valid | 10 | Files parse as valid GenBank with LOCUS/FEATURES/ORIGIN |
| STR_core_repeat annotations | 20 | Each file has annotation named STR_core_repeat |
| forensic_markers group | 10 | Annotations are in the forensic_markers group |
| Annotation coordinates valid | 15 | Annotation spans are within expected ranges for each locus |
| Report file exists with content | 15 | str_profile_report.txt exists with all 3 loci mentioned |
| Report contains repeat motifs | 15 | Report mentions correct repeat motifs (TATC/TCTA/AATG) |

## Verification Approach
- Parse annotated GenBank files for FEATURES section entries
- Check annotation names, groups, and coordinate ranges
- Parse report text for locus names and repeat motif strings
- Baseline recording: empty results/ directory at task start

## Anti-Gaming
- Do-nothing returns 0 (results/ is empty at start)
- Wrong-target gate: annotations must reference correct locus names
- Coordinate range validation prevents random annotation placement
