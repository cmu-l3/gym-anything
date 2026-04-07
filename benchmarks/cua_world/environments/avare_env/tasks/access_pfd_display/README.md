# Access PFD Display and Report Instrument Readings (`access_pfd_display@1`)

## Overview
This task requires the agent to navigate from Avare's main map view to the PFD (Primary Flight Display) tab — the synthetic instrument panel that displays attitude, altitude, airspeed, heading, and vertical speed indicators. The agent must open the PFD tab, confirm the instrument panel is rendered, and then return to the map view, demonstrating competence with Avare's multi-tab EFB interface.

## Rationale
**Why this task is valuable:**
- Tests navigation between Avare's primary application tabs (Map ↔ PFD)
- Verifies the agent can locate and activate a non-default view in a tabbed Android EFB
- Exercises understanding of aviation instrument display layouts
- Confirms the agent can return to the original view (round-trip navigation)

**Real-world Context:** A newly instrument-rated pilot flying a Cessna 172 is using Avare as a backup electronic flight instrument. During cruise flight, they want to cross-check their panel gyroscope readings against the GPS-derived PFD on their tablet. After confirming the instruments match, they switch back to the moving map for situational awareness.

## Task Description

**Goal:** Open Avare, navigate to the PFD (Primary Flight Display) tab so that the synthetic instrument panel is visible on screen, then switch back to the Map tab to confirm round-trip tab navigation works correctly.

**Starting State:** Avare is launched and showing the main **Map** view.

**Expected Actions:**
1. From the Map view, locate the tab bar or navigation mechanism.
2. Tap the **PFD** tab to switch to the Primary Flight Display.
3. Confirm the PFD is displayed (instruments visible).
4. Switch back to the **Map** tab.
5. Confirm the moving map view is displayed again.

**Final State:** Avare should be showing the **Map** tab, and the agent's trajectory should include clear evidence of having visited the PFD tab during the session.

## Verification Strategy

### Primary Verification: VLM Trajectory Analysis
The agent's screen recording trajectory is analyzed frame-by-frame. The verifier checks:
1. **PFD tab visited** — At least one trajectory frame shows the PFD instrument panel.
2. **Map tab restored** — The final frame shows the map view.
3. **Workflow progression** — Frames show a logical sequence: Map → PFD → Map.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Avare running | 10 | App is active at end of task |
| PFD Visited | 40 | Trajectory shows PFD instrument panel |
| Map Restored | 40 | Final state shows Map view |
| Workflow | 10 | Logical sequence confirmed |
| **Total** | **100** | |

**Pass Threshold:** 70 points