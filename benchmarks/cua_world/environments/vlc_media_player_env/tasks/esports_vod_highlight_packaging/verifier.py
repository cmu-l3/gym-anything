#!/usr/bin/env python3
"""
Verifier for Esports VOD Highlight Packaging.

Programmatic Validation:
1. Verifies generation of output MP4 files (during task timeframe).
2. Verifies correct duration (±1.5s tolerance).
3. Verifies H.264 video and AAC audio properties.
4. Verifies resolution (1920x1080).
5. Verifies JSON manifest correctness.

VLM Trajectory Validation:
6. Validates the process to ensure the watermark (overlay filter) and 
   audio normalization (dynaudnorm, loudnorm, or volume filter) were applied.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROCESS_PROMPT = """You are analyzing the command-line or GUI trajectory of an agent completing a video editing task.
The agent needs to apply two specific filters:
1. A visual watermark (burning 'team_logo.png' into the top-right corner using an overlay).
2. Audio normalization (compressing/normalizing the dynamic range).

Review the provided screenshots of the agent's work (e.g., ffmpeg commands typed in the terminal, or VLC GUI filters).

Questions:
1. Did the agent explicitly add a watermark/overlay filter? (e.g., `-vf "overlay=..."` or adding a logo filter in VLC).
2. Did the agent explicitly add an audio normalization filter? (e.g., `-af "loudnorm"`, `-af "dynaudnorm"`, or a volume compressor).

Provide your response strictly in the following JSON format:
{
    "watermark_applied": true/false,
    "normalization_applied": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what commands or UI elements prove the filters were applied."
}
"""

def _query_vlm(query_vlm_func, prompt, images):
    if not query_vlm_func or not images:
        return {"watermark_applied": False, "normalization_applied": False}
    try:
        result = query_vlm_func(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
    return {"watermark_applied": False, "normalization_applied": False}

def verify_esports_vod_highlight_packaging(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    expected_files = metadata.get("expected_files", [])
    expected_durations = metadata.get("expected_durations", {})
    tolerance = metadata.get("duration_tolerance_sec", 1.5)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Fetch File Analysis Results
    # ---------------------------------------------------------
    ffprobe_results = {}
    temp_ffprobe = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/ffprobe_results.json", temp_ffprobe.name)
        with open(temp_ffprobe.name, "r") as f:
            ffprobe_results = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Failed to read file analysis: {e}")
    finally:
        if os.path.exists(temp_ffprobe.name):
            os.unlink(temp_ffprobe.name)
            
    # ---------------------------------------------------------
    # 2. Fetch Manifest
    # ---------------------------------------------------------
    manifest_data = {}
    temp_manifest = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/manifest_exported.json", temp_manifest.name)
        with open(temp_manifest.name, "r") as f:
            manifest_data = json.load(f)
    except Exception:
        feedback_parts.append("Manifest not found or invalid JSON.")
    finally:
        if os.path.exists(temp_manifest.name):
            os.unlink(temp_manifest.name)

    # ---------------------------------------------------------
    # Programmatic Scoring (65 points total)
    # ---------------------------------------------------------
    # A. File Existence & Creation (15 points)
    files_exist = sum([1 for fname in expected_files if ffprobe_results.get(fname, {}).get("exists", False)])
    if files_exist == 3:
        # Check anti-gaming
        created_during = all([ffprobe_results.get(fname, {}).get("created_during_task", False) for fname in expected_files])
        if created_during:
            score += 15
            feedback_parts.append("All output files generated during task.")
        else:
            score += 5
            feedback_parts.append("Files exist but timestamps indicate they may not be newly generated.")
    else:
        feedback_parts.append(f"Missing {3 - files_exist} expected output files.")
        
    # B. Exact Durations (25 points)
    duration_pts = 0
    for fname in expected_files:
        f_data = ffprobe_results.get(fname, {})
        if f_data.get("exists"):
            ffp = f_data.get("ffprobe", {})
            try:
                dur = float(ffp.get("format", {}).get("duration", 0))
                expected = expected_durations.get(fname, 0)
                if abs(dur - expected) <= tolerance:
                    duration_pts += (25 / 3.0)
                else:
                    feedback_parts.append(f"{fname} duration ({dur}s) is out of tolerance (expected ~{expected}s).")
            except (ValueError, TypeError):
                pass
    score += duration_pts
    
    # C. Format Compliance (15 points)
    format_pts = 0
    for fname in expected_files:
        f_data = ffprobe_results.get(fname, {})
        if f_data.get("exists"):
            streams = f_data.get("ffprobe", {}).get("streams", [])
            has_h264 = False
            has_aac = False
            has_res = False
            for s in streams:
                if s.get("codec_name") == "h264":
                    has_h264 = True
                    if s.get("width") == 1920 and s.get("height") == 1080:
                        has_res = True
                if s.get("codec_name") == "aac":
                    has_aac = True
            if has_h264 and has_aac and has_res:
                format_pts += 5
            else:
                feedback_parts.append(f"{fname} missing required codec or wrong resolution.")
    score += format_pts
    
    # D. Manifest JSON (10 points)
    if "highlights" in manifest_data and isinstance(manifest_data["highlights"], list):
        if len(manifest_data["highlights"]) == 3:
            has_req_keys = True
            for entry in manifest_data["highlights"]:
                if not all(k in entry for k in ("filename", "duration_seconds", "title", "watermarked")):
                    has_req_keys = False
            if has_req_keys:
                score += 10
                feedback_parts.append("Manifest is fully compliant.")
            else:
                score += 5
                feedback_parts.append("Manifest missing required keys in objects.")
        else:
            feedback_parts.append("Manifest 'highlights' array does not contain exactly 3 items.")

    # ---------------------------------------------------------
    # VLM Trajectory Scoring (35 points total)
    # ---------------------------------------------------------
    if query_vlm and traj:
        # Sample frames showing active work
        frames = sample_trajectory_frames(traj, n=5)
        vlm_res = _query_vlm(query_vlm, VLM_PROCESS_PROMPT, frames)
        
        # E. Visual Watermark Filter Applied (20 points)
        if vlm_res.get("watermark_applied", False):
            score += 20
            feedback_parts.append("VLM confirmed watermark overlay filter application.")
        else:
            feedback_parts.append("VLM did NOT detect watermark filter commands.")
            
        # F. Audio Normalization Filter Applied (15 points)
        if vlm_res.get("normalization_applied", False):
            score += 15
            feedback_parts.append("VLM confirmed audio normalization filter application.")
        else:
            feedback_parts.append("VLM did NOT detect audio normalization filter commands.")
    else:
        feedback_parts.append("VLM query unavailable for trajectory validation.")

    # Calculate final status
    key_criteria_met = files_exist == 3 and duration_pts > 16  # Must have all files and mostly right durations
    passed = (score >= 70) and key_criteria_met
    
    return {
        "passed": passed,
        "score": round(score, 1),
        "feedback": " | ".join(feedback_parts)
    }