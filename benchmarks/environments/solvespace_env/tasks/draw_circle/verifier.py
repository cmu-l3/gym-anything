#!/usr/bin/env python3
"""Stub verifier for draw_circle task.
Actual verification is done externally via VLM evaluators.

Programmatic checks (for future implementation) would:
1. Check /home/ga/Documents/SolveSpace/circle.slvs exists and is non-empty
2. Parse the .slvs file to verify:
   - At least one circle request (type CIRCLE in the slvs format)
   - A diameter/radius constraint with value ~25mm (50mm diameter)
3. Use solvespace-cli to validate the sketch is fully constrained
"""


def verify_draw_circle(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
