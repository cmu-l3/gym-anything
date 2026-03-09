# UGENE Environment Evidence Documentation

## Environment Overview
- **Application**: UGENE 53.0 - Integrated Bioinformatics Suite
- **Base Image**: ubuntu-gnome-systemd_highres
- **Resources**: 4 CPU, 6GB RAM, no GPU, network enabled
- **Tasks**: 2 tasks (align_hemoglobin_sequences, build_phylogenetic_tree)

## Verification Checklist

### Installation (pre_start hook)
- [x] UGENE 53.0 downloaded from GitHub releases (tar.gz)
- [x] System dependencies installed (Qt5, OpenGL, xdotool, wmctrl, scrot)
- [x] UGENE wrapper script created at /usr/local/bin/ugene
- [x] Real hemoglobin beta sequences downloaded from UniProt (8 species)
- [x] Real cytochrome c sequences downloaded from UniProt (8 species) - all verified as cytochrome c
- [x] Real PDB structure (4HHB hemoglobin) downloaded from RCSB
- [x] Human insulin GenBank record downloaded from NCBI

### Setup (post_start hook)
- [x] User directories created (~/.config/UGENE, ~/UGENE_Data)
- [x] Sample data copied to user workspace
- [x] UGENE preferences configured to suppress first-run dialogs
- [x] Desktop launcher created
- [x] Warm-up launch completed successfully (UGENE window detected in 2s)

### Task: align_hemoglobin_sequences
- [x] FASTA file with 8 real protein sequences verified
- [x] UGENE launches and opens correctly
- [x] File opened via Ctrl+O dialog with correct path
- [x] Sequences loaded in multiple alignment viewer
- [x] All 8 species visible: Human (P68871), Mouse (P02088), Chicken (P02112), Frog (P02132), Zebrafish (Q90485), Cow (P02070), Horse (P02062), Pig (P02067)
- [x] Task start state verified via visual_grounding MCP tool
- [x] Status bar shows: 8 sequences, 147 columns
- [x] Agent can perform MUSCLE alignment from this start state

### Task: build_phylogenetic_tree
- [x] Cytochrome c FASTA file with 8 real protein sequences verified
- [x] All sequences confirmed as cytochrome c (P04657=Drosophila, P62895=Pig fixed from incorrect accessions)
- [x] File opened via Ctrl+O dialog with correct path
- [x] Sequences loaded in multiple alignment viewer
- [x] All 8 species visible: Human (P99999), Chicken (P67881), Neurospora crassa (P00048), Cannabis sativa (P00053), Yeast (P00044), Drosophila (P04657), Horse (P00004), Pig (P62895)
- [x] Task start state verified via visual_grounding MCP tool
- [x] Status bar shows: 8 sequences, 111 columns
- [x] Agent can perform MUSCLE alignment and phylogenetic tree building from this state

## Evidence Screenshots

### Early Development (Phase 6)
1. `01_ugene_welcome_screen.png` - UGENE welcome screen after launch
2. `02_fasta_loading_dialog.png` - Sequence reading options dialog showing real hemoglobin data
3. `03_alignment_viewer.png` - Multiple alignment viewer with 8 hemoglobin sequences
4. `04_task_start_state_alignment.png` - Task start state for alignment

### Interactive Testing with visual_grounding (Phase 7)
5. `05_final_alignment_task_visual_grounding.png` - Alignment task start state verified via visual_grounding
6. `06_phylogenetic_task_cytochrome_c_loaded.png` - Phylogenetic task with cytochrome c data loaded

### Clean Final Test (Phase 7)
7. `07_clean_final_test_alignment_task.png` - Fresh VM boot, alignment task start state (hemoglobin)
8. `08_clean_final_test_phylogenetic_task.png` - Fresh VM boot, phylogenetic task start state (cytochrome c, fixed accessions)
9. `09_verified_all_hbb_final.png` - All 8 hemoglobin sequences confirmed HBB (beta) after accession fix

## Log Excerpts (from clean final test)

### pre_start hook (install_ugene.sh)
```
=== Installing UGENE Bioinformatics Suite ===
=== Downloading UGENE 53.0 ===
Downloaded UGENE 53.0
=== Downloading Real Bioinformatics Data ===
Downloading hemoglobin beta protein sequences from UniProt...
UniProt batch download failed, trying individual downloads...
Downloaded 8 hemoglobin beta sequences
Downloading human insulin gene GenBank record from NCBI...
Downloading hemoglobin crystal structure (PDB 4HHB) from RCSB...
Downloading cytochrome c protein sequences from UniProt...
UniProt batch download failed for cytochrome c, trying individual...
Downloaded 8 cytochrome c sequences
=== UGENE installation complete ===
UGENE location: /opt/ugene
Data location: /opt/ugene_data
total 492
-rwxr-xr-x 1 root root   1617 Mar  3 20:40 cytochrome_c_multispecies.fasta
-rwxr-xr-x 1 root root 473769 Mar  3 20:40 hemoglobin_4HHB.pdb
-rwxr-xr-x 1 root root   1887 Mar  3 20:40 hemoglobin_beta_multispecies.fasta
-rwxr-xr-x 1 root root  10477 Mar  3 20:40 human_insulin_gene.gb
```

### post_start hook (setup_ugene.sh)
```
=== Setting up UGENE for user ga ===
Performing warm-up launch of UGENE...
UGENE window detected after 2s
Closing warm-up UGENE instance...
```

### pre_task hook - align_hemoglobin_sequences (setup_task.sh)
```
=== Setting up align_hemoglobin_sequences task ===
Input file has 8 sequences
Launching UGENE...
UGENE window detected after 2s
Opening hemoglobin FASTA file via File dialog...
Selecting alignment viewing mode...
File loaded in alignment viewer
Initial screenshot saved
=== Task setup complete ===
```

### pre_task hook - build_phylogenetic_tree (setup_task.sh)
```
=== Setting up build_phylogenetic_tree task ===
Input file has 8 sequences
Launching UGENE...
UGENE window detected after 2s
Opening cytochrome c FASTA file via File dialog...
Selecting alignment viewing mode...
File loaded in alignment viewer
Initial screenshot saved
=== Task setup complete ===
```

## Real Data Sources
- **Hemoglobin beta sequences**: UniProt accessions P68871 (Human), P02088 (Mouse), P02112 (Chicken), P02132 (Frog/Xenopus), Q90485 (Zebrafish), P02070 (Cow), P02062 (Horse), P02067 (Pig) — all verified HBB (beta subunit)
- **Cytochrome c sequences**: UniProt accessions P99999 (Human), P67881 (Chicken), P00048 (Neurospora crassa), P00053 (Cannabis sativa), P00044 (Yeast), P04657 (Drosophila), P00004 (Horse), P62895 (Pig)
- **PDB structure**: RCSB PDB ID 4HHB (deoxyhemoglobin crystal structure)
- **GenBank record**: NCBI NM_000207.3 (human insulin gene)

## Timing (clean final test)
- Environment setup (pre_start + post_start): ~86 seconds
- Task-specific hooks: ~30 seconds
- Total from reset to ready: ~116 seconds

## Data Quality Fixes

### Cytochrome c accession fixes
- P04148 downloaded as "Fibrohexamerin" (NOT cytochrome c) → Fixed to P04657 (CYC1_DROME, Drosophila cytochrome c)
- P62894 downloaded as CYC_BOVIN (Bovine) instead of intended pig → Fixed to P62895 (CYC_PIG, Pig cytochrome c)

### Hemoglobin alpha/beta fix
- P02016 (HBA_CYPCA, Carp alpha subunit) → Fixed to P02132 (HBB1_XENLA, Frog beta subunit)
- Q90487 (HBA_DANRE, Zebrafish alpha subunit) → Fixed to Q90485 (HBB2_DANRE, Zebrafish beta subunit)
- All 8 hemoglobin sequences now confirmed as HBB (beta subunit) — verified via visual_grounding

### Bundled data fallback
- Both FASTA files now bundled in assets/ directory as local fallback if UniProt is unavailable
- install_ugene.sh wired to fall back to /workspace/assets/ copies if download yields <8 sequences

### Setup script robustness
- Sequence Reading Options dialog radio button selection now uses keyboard Down arrows instead of pixel clicks
- OK button click retained (stable position in centered dialog)
