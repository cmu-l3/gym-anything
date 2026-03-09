# Vaccine Epitope Conservation Analysis

## Domain Context
Universal influenza vaccine design targets epitope regions that are conserved across diverse viral subtypes. Computational immunologists align hemagglutinin sequences from many strains, identify regions with high sequence conservation (>80% identity), and annotate them as potential vaccine epitope candidates. Conserved regions of >=9 amino acids can serve as T-cell epitope targets.

## Goal
Align 12 influenza HA protein sequences using MAFFT, identify conserved epitope regions, annotate them, extract consensus sequence, and produce multi-format outputs plus a vaccine target report.

## Starting State
- UGENE launched to welcome screen
- 12 HA sequences in `~/UGENE_Data/vaccine/influenza_HA_strains.fasta`
- Empty results directory

## Success Criteria (100 points total)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Consensus FASTA file | 10 | HA_consensus.fasta exists with valid FASTA |
| Annotated alignment file | 15 | HA_alignment_annotated.aln exists with ClustalW format |
| Stockholm format export | 10 | HA_alignment.sto exists with valid Stockholm format |
| conserved_epitope annotations | 20 | Alignment has conserved_epitope annotations in vaccine_targets group |
| Annotations have valid coordinates | 10 | Epitope annotations span >=9 amino acids |
| Epitope report exists | 15 | Report lists epitopes with positions and conservation scores |
| Report ranks top 3 candidates | 10 | Report includes a ranking of top epitope candidates |
| All 12 sequences in alignment | 10 | Alignment contains all input sequences |

## Anti-Gaming
- Do-nothing: results/ empty → score=0
- Annotations must have conserved_epitope name and vaccine_targets group
- Coordinate validation: epitopes must span >=9 residues
- Report must contain numeric conservation percentages
