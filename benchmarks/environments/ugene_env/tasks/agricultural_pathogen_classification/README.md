# Agricultural Pathogen Classification

## Domain Context
Plant pathologists use ITS (Internal Transcribed Spacer) sequences as the universal barcode for fungal identification. When a farmer submits diseased crop samples, the lab sequences the ITS region and compares it against known pathogen reference databases using multiple sequence alignment and phylogenetic tree inference. The closest phylogenetic neighbor identifies the pathogen species, enabling targeted disease management recommendations.

## Goal
Classify an unknown wheat fungal pathogen by performing ClustalW alignment of its ITS sequence against 10 known wheat pathogen references, building a Maximum Likelihood phylogenetic tree, and producing multi-format outputs plus a diagnostic report.

## Starting State
- UGENE launched to welcome screen
- Unknown pathogen ITS and 10 reference sequences in `~/UGENE_Data/agriculture/`
- Empty results directory

## Success Criteria (100 points total)

| Criterion | Points | Description |
|-----------|--------|-------------|
| PHYLIP alignment file | 15 | pathogen_alignment.phy exists with valid PHYLIP format |
| ClustalW alignment file | 10 | pathogen_alignment.aln exists with valid ClustalW format |
| Newick tree file | 15 | pathogen_tree.nwk exists with valid Newick syntax |
| All 11 sequences in alignment | 15 | Alignment contains unknown + all 10 references |
| Tree contains all taxa | 15 | Tree has 11 leaf nodes |
| Diagnostic report exists | 15 | Report identifies pathogen and recommends management |
| Correct pathogen identified | 15 | Report identifies Fusarium graminearum as closest match |

## Anti-Gaming
- Do-nothing: results/ empty → score=0
- Sequence count validation (must be exactly 11)
- Tree leaf count must match alignment sequence count
- Wrong-target: report must mention Fusarium (not generic text)
