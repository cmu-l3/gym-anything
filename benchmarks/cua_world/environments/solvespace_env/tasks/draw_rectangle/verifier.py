#!/usr/bin/env python3
"""Stub verifier for draw_rectangle task.
Actual verification is done externally via VLM evaluators.

Programmatic checks (for future implementation) would:
1. Check /home/ga/Documents/SolveSpace/rectangle.slvs exists and is non-empty
2. Parse the .slvs file (text format) to verify:
   - At least 4 line segment requests (the rectangle sides)
   - Horizontal/vertical constraints applied to the edges
   - Distance constraints for 80mm width and 50mm height
3. Use solvespace-cli (if available) to validate the geometry is fully constrained
"""


def verify_draw_rectangle(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
