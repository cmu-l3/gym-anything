# openvsp_multi_format_export

## Task Description

A CFD pre-processing engineer needs to deliver the eCRM-001 research wing-body model in three formats for three downstream analysis teams. This is a realistic multi-deliverable scenario where different groups require the same geometry in different representations.

**Realistic context**: Export pipeline management is standard in aerospace engineering. Engineers regularly export from a master parametric model to multiple downstream formats, each with specific naming conventions imposed by the receiving team's workflows.

## What the Agent Must Do

1. Open `/home/ga/Documents/OpenVSP/eCRM-001_wing_tail.vsp3` in OpenVSP
2. Export STL mesh → `/home/ga/Documents/OpenVSP/exports/eCRM001_mesh.stl`
3. Export Cart3D mesh (.tri) → `/home/ga/Documents/OpenVSP/exports/eCRM001_cart3d.tri`
4. Export Degen Geom CSV → `/home/ga/Documents/OpenVSP/exports/eCRM001_degengeom.csv`

All three files must be created through OpenVSP's File > Export menu with the exact filenames specified.

## Export Formats

| Format | Menu Path | Expected Content |
|--------|-----------|-----------------|
| STL | File > Export > STL (*.stl) | Binary or ASCII STL with `solid` or `facet` keyword |
| Cart3D | File > Export > Cart3D (*.tri) | Text file starting with node/element count header |
| Degen Geom | Analysis > Degen Geom | CSV with `# DegenGeom` header |

## Scoring (100 pts)

- STL file exists and has valid STL content: 33 pts
- Cart3D .tri file exists with valid header: 34 pts
- DegenGeom CSV exists with valid header: 33 pts

Pass threshold: 67 (at least 2 of 3 exports correct).

## Files

- `setup_task.sh` — copies eCRM model, creates exports directory, clears stale exports
- `export_result.sh` — records existence and first-line content of each expected output file
- `verifier.py` — checks each file exists and has format-appropriate content signature

## Difficulty Justification

**hard**: Three separate exports through different menu paths with exact naming requirements. The agent must navigate three different export dialogs and rename output files correctly each time. No anatomical or domain-specific knowledge required, but multi-step GUI navigation across different submenus.
