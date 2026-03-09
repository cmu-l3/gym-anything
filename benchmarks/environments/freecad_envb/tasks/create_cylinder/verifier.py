#!/usr/bin/env python3
"""Stub verifier for create_cylinder task.
Actual verification is done externally via VLM evaluators.

Programmatic verification logic (for reference):
  - Unzip /home/ga/Documents/FreeCAD/cylinder_model.FCStd
  - Parse Document.xml
  - Find object of type "Part::Cylinder"
  - Check Radius=15, Height=50 (within 0.1mm tolerance)
"""

def verify_create_cylinder(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
