#!/usr/bin/env python3
"""
Verifier for worm_straighten_morphometry task.

Checks:
1. Output files exist and were created during task (anti-gaming).
2. Straightened image geometry (should be landscape, indicating straightening).
3. CSV contains data points (profile).
4. Report contains valid length measurement in microns.
5. VLM verification of trajectory (tracing -> straightening -> plotting).
"""

import json
import os
import tempfile
import logging
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed
sys.path.insert(0, str(Path(__file__).parent.parent))
try:
    from vlm_utils import query_vlm, sample_trajectory_frames
except ImportError:
    # Fallback/Stub if not running in full framework
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_worm_straightening(traj, env_info, task_info):
    """
    Verify C. elegans straightening and morphometry task.
    """
    # 1. Setup and retrieve result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    outputs = result.get("outputs", {})
    measurements = result.get("measurements", {})
    
    # 2. Programmatic Verification (70 points)

    # Criterion A: Straightened Image (20 pts)
    # Must exist, be created during task, and be "straight" (width > height)
    img_info = outputs.get("straightened_image", {})
    if img_info.get("exists") and img_info.get("created_during_task"):
        if img_info.get("is_landscape"):
            score += 20
            feedback.append("Straightened image valid (20/20)")
        else:
            score += 10
            feedback.append("Straightened image exists but aspect ratio wrong (vertical?) (10/20)")
    else:
        feedback.append("Straightened image missing or old (0/20)")

    # Criterion B: Profile Plot Image (10 pts)
    plot_info = outputs.get("profile_plot_image", {})
    if plot_info.get("exists") and plot_info.get("created_during_task"):
        score += 10
        feedback.append("Profile plot saved (10/10)")
    else:
        feedback.append("Profile plot missing (0/10)")

    # Criterion C: CSV Data (15 pts)
    csv_info = outputs.get("profile_csv", {})
    if csv_info.get("exists") and csv_info.get("created_during_task"):
        row_count = csv_info.get("row_count", 0)
        if row_count >= 50:
            score += 15
            feedback.append(f"Profile data CSV valid ({row_count} rows) (15/15)")
        else:
            score += 5
            feedback.append(f"Profile data CSV exists but too short ({row_count} rows) (5/15)")
    else:
        feedback.append("Profile data CSV missing (0/15)")

    # Criterion D: Measurements Report (25 pts)
    report_info = outputs.get("report", {})
    if report_info.get("exists") and report_info.get("created_during_task"):
        reported_len = measurements.get("reported_length")
        
        # Valid length for C. elegans in this dataset is typically 400-1200 um
        # We allow a generous range 200-1500 to account for larvae/adults/errors
        if reported_len is not None:
            if 200 <= reported_len <= 1500:
                score += 25
                feedback.append(f"Reported length reasonable ({reported_len} um) (25/25)")
            else:
                score += 15
                feedback.append(f"Reported length out of expected range ({reported_len} um) (15/25)")
        else:
            score += 10
            feedback.append("Report exists but length not parsed (10/25)")
    else:
        feedback.append("Measurements report missing (0/25)")

    # 3. VLM Verification (30 points)
    # Check trajectory for tool usage: Segmented Line -> Straighten -> Plot
    
    frames = sample_trajectory_frames(traj, n=6)
    vlm_score = 0
    
    if frames:
        prompt = """
        Analyze these screenshots of a user working in Fiji/ImageJ on a worm image.
        I am looking for evidence of three specific steps:
        1. TRACING: Drawing a line (often yellow) along the curved body of a worm.
        2. STRAIGHTENING: A result window showing a straight rectangular worm image.
        3. PROFILING: A "Plot Profile" window showing a graph of intensity.
        
        Return JSON:
        {
            "tracing_seen": boolean,
            "straight_result_seen": boolean,
            "plot_seen": boolean
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                if parsed.get("tracing_seen"): 
                    vlm_score += 10
                    feedback.append("VLM: Tracing step observed (10/10)")
                if parsed.get("straight_result_seen"): 
                    vlm_score += 10
                    feedback.append("VLM: Straightened result observed (10/10)")
                if parsed.get("plot_seen"): 
                    vlm_score += 10
                    feedback.append("VLM: Profile plot observed (10/10)")
            else:
                feedback.append("VLM analysis failed (0/30)")
        except Exception:
            feedback.append("VLM error (0/30)")
    else:
        feedback.append("No trajectory frames available (0/30)")

    score += vlm_score

    # Final Result
    # Need at least 60 points AND the straightened image must exist
    straightened_image_valid = (img_info.get("exists") and 
                                img_info.get("created_during_task") and 
                                img_info.get("is_landscape"))
    
    passed = (score >= 60) and straightened_image_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }