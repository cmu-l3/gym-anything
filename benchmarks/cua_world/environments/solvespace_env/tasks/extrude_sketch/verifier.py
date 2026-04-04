#!/usr/bin/env python3
"""Stub verifier for extrude_sketch task.
Actual verification is done externally via VLM evaluators.

Programmatic checks (for future implementation) would:
1. Check /home/ga/Documents/SolveSpace/block.slvs exists and is non-empty
2. Parse the .slvs file to verify:
   - At least 2 groups: a sketch group and an extrude group
   - The sketch group contains a rectangle (4 line segments with constraints)
   - The extrude group (type EXTRUDE in slvs format) with depth ~15mm
   - Width constraint ~40mm and height constraint ~30mm in the sketch
3. Use solvespace-cli to confirm the solid is valid
"""


def verify_extrude_sketch(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
