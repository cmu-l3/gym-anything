#!/usr/bin/env python3
"""Stub verifier for pipeline_corridor_inspection_deployment task.

Actual verification is done externally via VLM evaluators.

This task requires the agent to:
1. Read the ops package and configure 5 vehicle parameters via QGC Parameters.
2. Create a Corridor Scan mission along a pipeline route with FLIR Vue Pro R 640
   thermal camera specs (altitude calculated from GSD formula: ~46m).
3. Set up an inclusion geofence polygon (4 vertices) and circular exclusion zone.
4. Place 2 emergency rally points at designated coordinates.
5. Save the complete plan (mission + fence + rally) to a single .plan file.
"""


def verify_pipeline_corridor_inspection(traj, env_info, task_info):
    """Stub verifier -- real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier -- VLM evaluation is external"
    }
