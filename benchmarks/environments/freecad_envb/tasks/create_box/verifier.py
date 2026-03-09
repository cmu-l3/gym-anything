#!/usr/bin/env python3
"""Stub verifier for create_box task.
Actual verification is done externally via VLM evaluators.

Programmatic verification logic (for reference):
  - Unzip /home/ga/Documents/FreeCAD/box_model.FCStd
  - Parse Document.xml
  - Find object of type "Part::Box"
  - Check Length=60, Width=40, Height=25 (within 0.1mm tolerance)
"""

def verify_create_box(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
