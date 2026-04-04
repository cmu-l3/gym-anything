# Task: forensic_craniometric_protocol

## Overview

**Professional Context**: Forensic anthropology — skeletal identification and biological profile estimation from cranial CT imaging.

Forensic anthropologists use CT data from unidentified remains to estimate biological profile parameters (sex, age, ancestry, stature) using standardized craniometric measurements. The procedure involves placing measurements at defined anatomical landmarks following protocols such as those described in Howells (1973), Bass (2005), and the FORDISC software system. CT-based craniometry is increasingly standard practice because it is non-destructive, repeatable, and archivable.

**Occupational Category**: Healthcare Practitioners and Technical / Life, Physical, and Social Science Occupations

**Economic significance**: Forensic anthropologists, physical anthropologists, and anatomists comprise a significant professional group using scientific imaging software including InVesalius.

---

## Goal

The agent must complete a full craniometric assessment protocol:
1. Create bone segmentation mask (any appropriate bone threshold)
2. Generate 3D bone surface
3. Place ≥10 linear measurements (including bilateral pairs and key cranial dimensions)
4. Export STL surface
5. Capture 3 orientation screenshots (norma frontalis, lateralis, verticalis)
6. Save complete project

---

## What Makes This Extremely Hard

**Scale of measurement requirement**: 10 measurements is the highest count for any InVesalius task in this environment. Existing hard tasks require 2–5 measurements. 10 requires significantly more navigation, tool usage, and anatomical knowledge.

**Triple deliverable format**: STL + 3 PNGs + .inv3 project = 5 output artifacts. This is more output artifacts than any existing task.

**Bilateral measurement protocol**: The task description explicitly requires bilateral pairs, meaning the agent must navigate to both sides of the skull at corresponding landmarks — it cannot just measure the easiest accessible points.

**No UI path provided**: The task description states the goal (biological profile documentation) and end state, not which menus or toolbars to use. The agent must independently discover how to:
- Access the measurement tool
- Navigate to specific anatomical locations
- Export STL
- Capture orientation screenshots

**Litmus test**: A competent InVesalius user without forensic anthropology context would complete 2–3 measurements and stop. A forensic anthropologist without InVesalius experience might know what to measure but struggle to navigate to each landmark. The task requires both domain knowledge and application knowledge.

---

## Starting State

- InVesalius 3 running with CT Cranium DICOM pre-loaded
- Output directory `/home/ga/Documents/forensic_case/` created
- Case brief at `/home/ga/Documents/forensic_case/case_brief.txt` with forensic context
- No pre-existing output files

---

## Scoring (100 pts, pass ≥ 70)

| Criterion | Points |
|-----------|--------|
| Project file saved and valid | 15 |
| ≥ 10 measurements in project | 25 |
| All measurements ≥ 15 mm (anatomically realistic) | 15 |
| STL file valid (≥ 10,000 triangles) | 20 |
| norma_frontalis.png valid (≥ 10 KB) | 10 |
| norma_lateralis.png valid (≥ 10 KB) | 8 |
| norma_verticalis.png valid (≥ 10 KB) | 7 |

---

## Expected Measurement Ranges (CT Cranium 0051)

Standard adult craniometric values:
- Maximum cranial length (glabella–opisthocranion): 165–195 mm
- Maximum cranial breadth (biparietal): 130–160 mm
- Cranial height (basion–bregma): 120–145 mm
- Temporal width (each side): 20–40 mm
- Orbital width (each side): 35–45 mm
- Mastoid height: 25–40 mm

All measurements should be ≥ 15 mm to exclude spurious short clicks.

---

## Anti-Gaming

- Baseline records absence of all output files before task starts
- STL triangle count ≥ 10,000 ensures real bone geometry (not a minimal stub)
- PNG minimum size ≥ 10 KB ensures actual screenshots (not blank images)
- Measurement count threshold ≥ 10 (highest in the environment) is not achievable by accident
- Minimum measurement value ≥ 15 mm rejects spurious very-short measurements
- Do-nothing baseline returns score = 0 (output-existence gate)
