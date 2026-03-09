# Task: clinical_app_tour

**Difficulty:** hard
**Domain:** Clinical Informatics / Medical Education
**Environment:** openice_env@0.1

## Overview

This task simulates a clinical informatics specialist conducting a structured teaching demonstration of the full OpenICE clinical application suite for new ICU staff. The agent must navigate the OpenICE Supervisor interface to create a simulated device adapter and launch all four available clinical demonstration applications, then synthesize observations into a written education guide.

## Clinical Context

ICU staff education and orientation is a critical component of safe medical device deployment. OpenICE (Open-source Integrated Clinical Environment) is a medical device interoperability platform developed by the MD PnP (Medical Device Plug-and-Play) program. New clinical staff need to understand what each application does, when to use it, and how it relates to patient safety before operating in live ICU environments.

## Goal

1. Create a **Simulated Multiparameter Monitor** device adapter in OpenICE Supervisor to provide live device data for demonstrations.
2. Systematically launch and explore all **four clinical demonstration applications**:
   - **Vital Signs** - Real-time patient vital signs monitoring from connected devices
   - **Xray Viewer** - Integration of medical imaging with live device data
   - **Patient ID** - Patient identification and context management across devices
   - **Infusion Safety** - Infusion pump safety interlocks and drug library integration
3. Write a **clinical education guide** to `/home/ga/Desktop/clinical_guide.txt` covering all four applications with structured clinical content.

## Scoring Breakdown (100 points total)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Multiparameter Monitor device created | 15 | Device adapter successfully instantiated in OpenICE |
| Vital Signs app launched | 10 | Vital Signs clinical application opened |
| Xray Viewer app launched | 10 | Xray Viewer clinical application opened |
| Patient ID app launched | 10 | Patient ID clinical application opened |
| Infusion Safety app launched | 10 | Infusion Safety clinical application opened |
| All 4 apps bonus | 5 | All four applications demonstrated (bonus) |
| Clinical guide file exists | 15 | Guide written to `/home/ga/Desktop/clinical_guide.txt` (>=300 bytes, written after task start) |
| Guide mentions all 4 app names | 15 | Guide contains dedicated sections for all 4 apps |
| Guide has clinical/interoperability content | 10 | Guide discusses clinical context, interoperability, patient safety |

**Pass threshold:** 65 points

### GATE Condition

If fewer than 3 apps are launched AND no guide file exists, the score is capped at 0 regardless of other criteria. The clinical guide is also required for passing — if the guide is absent and the raw score would otherwise reach the threshold, it is capped at threshold-1.

## Verification Approach

### App Launch Detection

Each clinical application logs a distinctive signature to `/home/ga/openice/logs/openice.log` when launched. The verifier uses a "new log lines only" approach: it records the log file size at task start and checks only log content appended after that point.

Detection patterns:
- **Vital Signs:** `VitalSigns`, `vital.?sign.*app`, `vital.?sign.*launch`, `vital.?sign.*open`
- **Xray Viewer:** `XrayViewer`, `xray`, `x.?ray.*view`, `xray.*app`, `xray.*launch`
- **Patient ID:** `PatientId`, `patient.?id.*app`, `patient.*id.*launch`, `PatientContext`
- **Infusion Safety:** `InfusionSafety`, `infusion.?safety.*app`, `infusion.*safety.*launch`, `safety.*infusion`

### Guide Content Analysis

The guide file is checked for:
- Each of the four application names (regex patterns matching common spellings)
- Clinical/interoperability vocabulary: `interoperab`, `clinical`, `patient.*safety`, `ICU`, `critical.*care`, `device.*integrat`

## What Makes This Task Hard

This is a **hard** task because:
- The agent is told which 4 apps to launch and what file to write, but is NOT given step-by-step UI navigation instructions
- The agent must explore the OpenICE Supervisor interface independently to find application launch controls
- Writing a high-quality 4-section clinical education guide requires synthesizing domain knowledge with observed interface behavior
- The agent must manage multiple sequential GUI interactions without explicit guidance on menu structure

## Files

| File | Purpose |
|------|---------|
| `README.md` | This documentation |
| `task.json` | Task specification and metadata |
| `setup_task.sh` | Pre-task environment setup |
| `export_result.sh` | Post-task result collection |
| `verifier.py` | Scoring and pass/fail determination |
