#!/usr/bin/env python3
"""
Verifier for Selective Measurement Deletion task.
Uses multi-signal verification including file timestamp analysis and VLM trajectory inspection.
"""

import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance in a medical imaging viewer (Weasis).
The agent was asked to:
1. Draw exactly 3 distance measurements (lines).
2. Select exactly 1 measurement.
3. Delete that single selected measurement.
4. Export a final view showing exactly 2 measurements remaining.

I will provide sampled frames from the agent's trajectory and the final exported screenshot.

Please analyze the sequence and verify the following:
1. "three_measurements_drawn": True if at SOME point in the trajectory, there are EXACTLY THREE distinct distance/line measurements visible on the medical image simultaneously.
2. "measurement_selected": True if at SOME point, one of the measurements is actively selected (usually indicated by control points/handles appearing at the ends of the line, or the line changing color).
3. "exactly_two_remaining": True if the FINAL exported image shows EXACTLY TWO distance/line measurements remaining on the image.

Output your response strictly as a valid JSON object:
{
    "three_measurements_drawn": true/false,
    "measurement_selected": true/false,
    "exactly_two_remaining": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what you see in the frames."
}
"""

def extract_json_from_vlm(response_str):
    """Safely extract JSON from a VLM response which might be wrapped in markdown blocks."""
    try:
        # First attempt: parse directly
        return json.loads(response_str)
    except Exception:
        # Second attempt: extract from markdown block
        match = re.search(r'