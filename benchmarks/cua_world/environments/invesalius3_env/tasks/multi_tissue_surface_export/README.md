# Task: multi_tissue_surface_export

## Overview

Multi-tissue 3D anatomical model preparation for surgical team review. This task reflects the workflow used by radiologists and surgical residents to prepare differentiated tissue reconstructions from CT data before team-based pre-operative planning.

## Domain Context

Neurosurgeons and radiologists use InVesalius to create separate 3D reconstructions of different tissue types from the same CT scan — bone, cortical bone, and soft tissue structures are visualized independently to understand their spatial relationships. Each tissue type is segmented with specific Hounsfield thresholds and exported as separate 3D mesh files for use in surgical simulation software or 3D printing.

## Goal

Given a loaded CT Cranium DICOM series, produce three separate segmented tissue models:
- **Full bone mask** (min HU ≥ 226): full bone envelope including cortical and trabecular bone
- **Compact cortical bone mask** (min HU ≥ 662): dense outer cortical shell only
- **Soft tissue mask** (max HU ≤ 225): non-bony soft tissue (brain, skin, muscles)

Each mask requires a generated 3D surface exported as STL:
- `/home/ga/Documents/tissue_exports/bone_tissue.stl`
- `/home/ga/Documents/tissue_exports/compact_bone.stl`
- `/home/ga/Documents/tissue_exports/soft_tissue.stl`

Project saved at: `/home/ga/Documents/tissue_exports/tissue_analysis.inv3`

## Starting State

- InVesalius 3 running with CT Cranium pre-loaded
- `/home/ga/Documents/tissue_exports/` directory already created
- No existing output files — clean workspace

## Agent Workflow (what must be discovered)

1. Create the first threshold mask (full bone) using segmentation panel
2. Generate 3D surface from first mask
3. Export that surface to the correct named file
4. Repeat for compact bone mask (different HU minimum)
5. Repeat for soft tissue mask (different HU maximum)
6. Save the project with all masks and surfaces

The agent must discover how to: create multiple distinct masks, generate surfaces per-mask, export each to differently-named files, and manage multiple surface/mask objects in one project.

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|-------------|
| Project file exists and is valid .inv3 | 20 | Tarball parse |
| ≥3 masks present in project | 25 | main.plist mask count |
| bone_tissue.stl exists and is valid STL | 20 | File parse + magic bytes |
| compact_bone.stl exists and is valid STL | 20 | File parse + magic bytes |
| soft_tissue.stl exists and is valid STL | 15 | File parse + magic bytes |

**Pass threshold: 70 points**

## Anti-Gaming Measures

- All three STL files must be independently present with different names
- Mask count requirement enforces creation of multiple segmentations
- Each STL is parsed for valid format (not just existence)

## Schema Reference

**InVesalius project (.inv3)** — gzipped tar archive containing:
- `main.plist`: project metadata including masks dict
- `mask_N.plist`: threshold_range [min, max]
