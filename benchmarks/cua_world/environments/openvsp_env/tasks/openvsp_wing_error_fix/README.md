# openvsp_wing_error_fix

## Task Description

An aerospace engineer working on a Cessna 210 performance study has received a corrupted OpenVSP model. During a data entry process, three wing geometry parameters were set to physically implausible values that no real Cessna 210 could have. The engineer must open the model, visually detect the anomalies, identify the incorrect wing section parameters, and correct them based on documented Cessna 210 specifications.

**Realistic context**: QA/review of parametric models is a daily task for aerodynamicists. Models passed between teams often contain transcription errors that must be caught before CFD or structural analysis begins. Finding and correcting such errors without being told exactly which fields are wrong requires both application proficiency and domain knowledge.

## What the Agent Must Do

1. Open `/home/ga/Documents/OpenVSP/cessna210_corrupt.vsp3` in OpenVSP
2. Visually inspect the 3D wing geometry to identify anomalies (extreme dihedral, unusual sweep, excessive twist)
3. Navigate to the Wing section properties (NormalWing component > XSec tab)
4. Identify and correct the three erroneous parameters to physically realistic values
5. Save the file back to the same path

## Injected Errors

The setup script injects three errors into the NormalWing sections:
- **Outboard section Dihedral**: changed from +2° to **-25°** (severely negative anhedral — visually obvious)
- **Root section Sweep (leading-edge)**: changed from 0° to **+42°** (delta-wing-like sweep — clearly wrong)
- **Root section Twist**: changed from +2° to **+22°** (extreme washout — visually distorts the section shape)

## Correct Values (Target Ranges)

| Parameter | Injected Error | Correct Range |
|-----------|---------------|---------------|
| Root section Sweep | 42.0° | [-3°, +8°] |
| Root section Twist | 22.0° | [-1°, +6°] |
| Outboard section Dihedral | -25.0° | [0°, +8°] |

## Files

- `setup_task.sh` — copies Cessna-210 model, injects three errors via Python XML manipulation
- `export_result.sh` — records file metadata and copies vsp3 for verification
- `verifier.py` — parses the fixed .vsp3 XML, checks parameter IDs against target ranges

## Difficulty Justification

**very_hard**: The description does not name which parameters are wrong — the agent must visually detect implausible geometry, navigate OpenVSP's XSec panel interface to find the correct parameters, and apply domain knowledge about Cessna 210 wing geometry. Three separate parameters across two different wing sections must all be fixed.
