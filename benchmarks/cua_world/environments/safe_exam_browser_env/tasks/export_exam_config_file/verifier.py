#!/usr/bin/env python3
"""
Verifier for export_exam_config_file task.

VERIFICATION METRICS:
1. File exists in ~/Downloads/ with .seb extension (30 pts)
2. File was created during the task (after start time) (20 pts)
3. File is non-empty (>100 bytes) (15 pts)
4. Config was NOT deleted from the database (10 pts)
5. VLM trajectory verification shows UI interaction (25 pts)
"""

import os
import json
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance on a web browser task.
The agent's goal was to export/download a Safe Exam Browser (SEB) configuration file named 'Anatomy Midterm Config'.

Please examine these trajectory frames and determine:
1. Did the agent navigate to the 'Configurations' -> 'Exam Configuration' section in the SEB Server interface?
2. Did the agent interact with the 'Anatomy Midterm Config' entry?
3. Is there evidence that the agent clicked an 'Export' or 'Download' action, or dealt with a browser download dialog?

Provide your reasoning, and then output a JSON object at the end with your boolean conclusions: