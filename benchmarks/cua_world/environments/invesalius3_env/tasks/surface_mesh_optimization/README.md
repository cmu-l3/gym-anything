# Task: surface_mesh_optimization

## Overview

3D printing mesh preparation pipeline using InVesalius 3 surface tools. This task reflects the workflow biomedical engineers use to convert raw CT-derived meshes into optimized, print-ready files.

## Domain Context

Physical medicine specialists and biomedical engineers increasingly use patient-specific 3D-printed anatomical models for surgical planning, implant design, and medical education. Raw 3D meshes generated directly from CT segmentation contain acquisition noise (jagged surface artifacts from partial-volume effects) and often have millions of triangles — far more than consumer or clinical 3D printers require. InVesalius provides built-in surface smoothing and decimation tools to prepare meshes for printing, making mesh optimization a standard step in the biomedical 3D printing workflow.

## Goal

Given a loaded CT Cranium DICOM series, produce an optimized, print-ready skull mesh:
1. Create a bone segmentation mask (appropriate HU thresholds)
2. Generate the initial 3D bone surface mesh
3. Apply mesh smoothing (≥15 iterations) to remove CT acquisition noise
4. Apply mesh decimation to reduce the triangle count (target: <500,000 triangles)
5. Export the optimized mesh in two formats:
   - PLY → `/home/ga/Documents/skull_optimized.ply`
   - Binary STL → `/home/ga/Documents/skull_optimized.stl`
6. Save project to `/home/ga/Documents/mesh_optimization.inv3`

## Starting State

- InVesalius 3 running with CT Cranium pre-loaded
- `/home/ga/Documents/3d_print_specs.txt` present (printer spec requirements)
- No existing output files — clean workspace

## Agent Workflow (what must be discovered)

1. Create threshold mask for bone
2. Generate 3D surface
3. Locate surface properties/tools (smoothing and decimation controls — typically accessed via right-click on surface or surface panel)
4. Apply smoothing iterations
5. Apply decimation to target triangle count
6. Export as PLY (a different format than the typical STL tasks)
7. Export as binary STL
8. Save project

The agent must discover: where surface editing tools are, what smoothing/decimation parameters to use, and how to export in PLY format in addition to STL.

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|-------------|
| PLY file exists and is valid PLY format | 25 | Magic bytes + header parse |
| PLY has ≥1,000 vertices (real geometry) | 15 | PLY header vertex count |
| STL file exists and is valid STL format | 25 | Binary/ASCII STL parse |
| STL has ≥1,000 triangles (real geometry) | 15 | Triangle count parse |
| Project file exists and is valid .inv3 | 20 | Tarball parse |

**Pass threshold: 70 points**

## Expected Values

- CT Cranium bone surface (unoptimized): typically 100K–600K triangles
- After smoothing: surface noise reduced but similar triangle count
- After decimation to <500K: 10K–500K triangles
- PLY file: ASCII or binary format; vertex/face counts in header

## Anti-Gaming Measures

- Requires BOTH PLY and STL formats (dual export, distinct tools)
- Both files must have real geometry (≥1,000 triangles/vertices)
- Project must be saved containing the surface

## Schema Reference

**PLY format** (Polygon File Format):
- Magic: "ply\n" at start
- Header contains: `element vertex N`, `element face M`
- Body: vertex coordinates then face indices

**STL format** — binary (80B header + 4B count + 50B per triangle) or ASCII ("solid ...")
