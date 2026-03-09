#!/usr/bin/env python3
"""Stub verifier for add_constraint task.
Actual verification is done externally via VLM evaluators.

Programmatic checks (for future implementation) would:
1. Check /home/ga/Documents/SolveSpace/side_constrained.slvs exists
2. Parse the .slvs file and compare constraint count with the original side.slvs
   - The new file should have at least 1 more constraint than the original
3. Verify the added constraint is type HORIZONTAL (slvs constraint type 20)
4. Check that the file was modified after task start time (timestamp check to
   prevent anti-gaming: "do nothing" must provably fail)
"""
import os


def verify_add_constraint(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
