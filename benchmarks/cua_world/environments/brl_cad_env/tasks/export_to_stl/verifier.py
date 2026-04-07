#!/usr/bin/env python3
"""Stub verifier for export_to_stl task.
Actual verification is done externally via VLM evaluators.

The VLM evaluator will check:
  - The g-stl command was executed successfully
  - /home/ga/Documents/BRLCAD/havoc_export.stl exists and is non-empty
  - The STL file contains valid geometry (triangle data)
"""

def verify_export_to_stl(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
