#!/usr/bin/env python3
"""Stub verifier for create_sketch task.
Actual verification is done externally via VLM evaluators.

Programmatic verification logic (for reference):
  - Unzip /home/ga/Documents/FreeCAD/sketch_model.FCStd
  - Parse Document.xml
  - Find an object of type "Sketcher::SketchObject"
  - Check it has at least 4 edges (4 lines forming a rectangle)
  - Check the sketch has constraints setting width=50 and height=30
"""

def verify_create_sketch(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
