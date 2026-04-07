#!/usr/bin/env python3
"""Stub verifier for sar_thermal_survey_preparation task.

Actual verification is done externally via VLM evaluators.

This task requires the agent to:
1. Create a Survey mission with custom thermal camera (FLIR Vue Pro R 640)
   and specific flight parameters (altitude, overlaps, hover-and-capture).
2. Add a Rally Point for emergency landing.
3. Configure 5 ArduPilot safety parameters via Vehicle Setup > Parameters.
4. Configure RTSP video source in QGC Application Settings.
5. Save mission plan, export parameters, and write a mission brief.
"""

import json
import os
import tempfile


def verify_sar_thermal_survey(traj, env_info, task_info):
    """Stub verifier -- real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier -- VLM evaluation is external"
    }
