#!/usr/bin/env python3
"""
Stub verifier for perspective_painting_extraction task.
Actual verification is done externally via VLM evaluators.

Task: Extract a painting from a gallery photograph by correcting perspective
distortion, cropping to the painting, scaling to 1200px wide, correcting
warm color cast, and exporting as painting_corrected.png.

Expected output: painting_corrected.png on Desktop
- Width: 1200 pixels
- Aspect ratio: approximately 4:3 (matching the original painting)
- Perspective corrected: rectangular edges, no trapezoidal distortion
- Color cast removed: neutral tones, no yellow-orange warmth
- Content: just the painting, no wall or frame visible
"""


def check_perspective_painting(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
