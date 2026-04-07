#!/usr/bin/env python3
"""Stub verifier for raytrace_moss_scene task.
Actual verification is done externally via VLM evaluators.

The VLM evaluator will check:
  - A framebuffer window appeared showing the ray-traced image
  - The rendered scene shows the moss.g objects (ellipsoid, torus, box, wedge)
  - The rendering completed successfully (not a blank/black framebuffer)
"""

def verify_raytrace_moss_scene(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
