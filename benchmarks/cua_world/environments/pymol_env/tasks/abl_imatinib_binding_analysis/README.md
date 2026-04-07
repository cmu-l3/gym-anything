# Task: Abl Kinase – Imatinib Binding Pocket Analysis

## Domain Context

Imatinib (Gleevec, STI-571) was the first molecularly targeted cancer drug approved for CML (chronic myelogenous leukemia). It works by binding to the inactive conformation of the Abl kinase domain, locking it in an off state. PDB:1IEP (Schindler et al., Science 2000) is the original crystal structure of Abl complexed with imatinib, and is one of the most-cited structures in drug discovery.

A key clinical challenge is drug resistance via the T315I "gatekeeper" mutation, which abolishes the critical hydrogen bond between imatinib and T315. Any complete binding analysis must identify this residue. Other important contacts include E286 (polar contact), D381/F382 (DFG motif), Y393 (activation loop), M318 (hydrophobic contact), and H361.

## Task Goal (Very Hard)

The agent must independently:
1. Load PDB:1IEP from RCSB into PyMOL
2. Identify the imatinib ligand (PDB residue name STI) and the binding pocket
3. Select all protein residues making direct contacts with imatinib
4. Create a publication-quality visualization of the drug in its binding site
5. Export the list of contacting residues to a plain text file
6. Render and save a PNG figure

No workflow hints are given — the agent must know PyMOL selection syntax, determine an appropriate contact cutoff, figure out the ligand name, and choose appropriate representations for a drug-binding figure.

## Expected Outputs

| File | Description |
|------|-------------|
| `/home/ga/PyMOL_Data/images/abl_imatinib.png` | PNG figure, >50KB, showing binding pocket |
| `/home/ga/PyMOL_Data/abl_contacts.txt` | Text file, one residue per line: `CHAIN RESI RESN` |

## Verification Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Figure exists and is substantial | 25 | PNG >50KB, created after task start |
| Contact file has ≥8 residues | 25 | Full pocket documented |
| T315 gatekeeper present | 25 | Critical resistance mutation site identified |
| ≥2 other key contacts (E286, D381, Y393, F382, M318) | 25 | Comprehensive binding contacts |

**Pass threshold: 70/100**

## Why This Is Very Hard

- Agent must determine the ligand residue name (STI) by inspecting the structure
- Must know PyMOL distance-based selection syntax (`byres protein within 4 of resn STI`)
- Must write residue data to a file from within PyMOL (iterate command or log redirect)
- Must choose appropriate representation (surface + sticks is standard for binding site figures)
- Must apply domain knowledge to recognize the completeness of their contact list

## Key Binding Residues (for verifier reference)

Based on published literature on 1IEP:
- **T315** – Gatekeeper; H-bond to imatinib amine; T315I mutation causes resistance
- **E286** – Salt bridge / H-bond with pyridine nitrogen
- **D381/F382** – DFG motif (critical kinase activation loop)
- **Y393** – Activation loop tyrosine
- **M318** – Hydrophobic contact
- **H361** – Polar contact
- **A380** – Backbone contact
- **K271** – Salt bridge

## Anti-gaming

- Output files are deleted in setup_task.sh before the agent starts
- Timestamp recorded at setup; verifier checks files are newer than task start
- T315 presence check requires genuine analysis (not template copying)
