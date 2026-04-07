# Task: Correct Misidentified Seismic Phase (`correct_phase_identification_scolv@1`)

## Overview
This task evaluates the agent's ability to perform precise manual quality control on seismic event solutions using SeisComP's `scolv` (Origin Locator View). The agent must identify a specific station arrival in an existing earthquake solution, change its phase type from a generic 'P' to a more specific phase ('PP'), and commit the updated solution to the database.

## Rationale
**Why this task is valuable:**
- **Seismological Analysis**: Tests the ability to modify phase associations, a critical daily task for analysts refining automated solutions.
- **Tool Proficiency**: Requires navigating the `scolv` GUI, specifically the Arrivals table or Picker interaction.
- **Database Interaction**: Verifies that the agent can successfully commit changes back to the system of record.
- **Real-world Relevance**: Automated pickers often misidentify secondary phases (like PP, pP, or PcP) as direct P waves. Analysts must correct these to improve location accuracy and depth resolution.

**Real-world Context:** An automated pipeline processed the Noto Peninsula earthquake and associated a pick at station `GE.TOLI` as a direct P-wave. However, due to the distance and waveform character, the senior analyst has determined it is actually a PP phase. You need to correct this label in the system.

## Task Description

**Goal:** Update the phase type for station **GE.TOLI** from 'P' to **'PP'** for the Noto Peninsula earthquake and commit the change to the database.

**Starting State:**
- SeisComP is running.
- The 2024 Noto Peninsula earthquake (M7.5) is loaded in the database.
- The event has an associated origin which includes a P-wave arrival for station `GE.TOLI`.
- `scolv` is open and maximized.

**Expected Actions:**
1. Load the Noto Peninsula earthquake event in `scolv`.
2. Locate the arrival for station `GE.TOLI` in the Arrivals tab.
3. Change the phase type from 'P' to 'PP'.
4. Commit the modified origin back to the database.

**Final State:**
- The current preferred origin for the event in the database shows `GE.TOLI` associated as a 'PP' phase.

## Verification Strategy

### Primary Verification: Database State (SQL)
The verifier queries the SeisComP database to confirm the phase change:
1. **Identify the preferred origin** for the Noto event.
2. **Find the arrival** corresponding to station `GE.TOLI`.
3. **Verify the `phase` attribute** equals 'PP'.
4. **Verify timestamps** (CreationInfo) to ensure the change was made during the task window.

### Secondary Verification: VLM Trajectory Analysis
Uses Vision-Language Model on the trajectory frames to verify that the agent actually interacted with the `scolv` GUI to make the change, preventing purely SQL-based gaming.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **GUI Interaction** | 20 | Trajectory shows scolv usage and phase editing |
| **Origin Updated** | 20 | New origin committed during task timeframe |
| **Station Found** | 10 | TOLI arrival exists in the new origin |
| **Phase Correct** | 50 | The GE.TOLI arrival phase is exactly 'PP' |
| **Total** | **100** | |

**Pass Threshold:** 70 points (Must get the phase correct and demonstrate legitimate workflow).