#!/usr/bin/env python3
"""Stub verifier for healthcare_it_architecture_review task.

Actual verification is done externally via VLM evaluators using
vlm_checklist.json. This stub is kept for framework compatibility.

The task asks the agent to create a 2-page architecture document:
  Page 1: ClearMed system architecture (microservices, databases, API gateway)
  Page 2: Patient admission workflow (cross-functional swimlane flowchart)
  Save as /home/ga/Documents/clearmed_architecture.eddx
  Export Page 1 as /home/ga/Documents/clearmed_architecture.png
"""


def verify_healthcare_it_architecture_review(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
