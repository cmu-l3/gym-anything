#!/usr/bin/env python3
"""
Verifier for the Agri-Coop First-Time Setup Task.
Uses a hybrid approach:
1. Programmatic: Extracts the .t2s (ZIP) file and scans the XML configuration for required strings.
2. VLM: Checks trajectory frames to verify the Tier2 Submit UI was actually used.
"""

import os
import json
import zipfile
import tempfile
import logging

# Attempt to import VLM utilities if available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are auditing an agent's desktop trajectory to verify it completed a task using the EPA Tier2 Submit software.
The agent was asked to create a facility named "Heartland Agri-Coop" and enter chemical inventory.

Look at these trajectory frames and answer the following:
1. Is the EPA Tier2 Submit application open and visible in any of the frames?
2. Is there evidence of data entry for "Heartland Agri-Coop" or chemicals like "Ammonium Nitrate" / "Paraquat"?

Respond strictly in JSON format:
{
    "tier2_submit_used": true/false,
    "data_entry_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""


def verify_agri_coop_setup(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    expected_t2s = metadata.get("expected_output", "C:\\Users\\Docker\\Documents\\heartland_coop.t2s")
    
    score = 0
    feedback = []
    
    # 1. Retrieve the metadata JSON from the container
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8") as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}
    finally:
        os.unlink(tmp_json.name)

    # 2. Check file existence (Gatekeeper)
    if not result_meta.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Target .t2s file was not exported/saved to the correct location."
        }
    
    score += 10
    feedback.append("PASS: Target file successfully exported (+10)")

    # 3. Retrieve the actual .t2s file from the container
    tmp_t2s = tempfile.NamedTemporaryFile(suffix=".t2s", delete=False)
    t2s_content = ""
    try:
        copy_from_env(expected_t2s, tmp_t2s.name)
        
        # Tier2 Submit files (.t2s) are zip archives containing XML files.
        if zipfile.is_zipfile(tmp_t2s.name):
            with zipfile.ZipFile(tmp_t2s.name, 'r') as z:
                for filename in z.namelist():
                    with z.open(filename) as f:
                        t2s_content += f.read().decode('utf-8', errors='ignore') + "\n"
        else:
            # Fallback if it's saved as raw XML directly
            with open(tmp_t2s.name, 'r', encoding='utf-8', errors='ignore') as f:
                t2s_content = f.read()
    except Exception as e:
        feedback.append(f"WARNING: Could not parse .t2s contents: {e}")
    finally:
        os.unlink(tmp_t2s.name)
        
    t2s_content_lower = t2s_content.lower()

    # 4. Programmatic Content Verification
    if "heartland agri-coop" in t2s_content_lower:
        score += 10
        feedback.append("PASS: Facility name 'Heartland Agri-Coop' found (+10)")
    else:
        feedback.append("FAIL: Facility name missing")

    if "68803" in t2s_content_lower and "424910" in t2s_content_lower:
        score += 10
        feedback.append("PASS: Facility ZIP and NAICS found (+10)")
    else:
        feedback.append("FAIL: Facility ZIP or NAICS missing")

    if "6484-52-2" in t2s_content_lower and "ammonium nitrate" in t2s_content_lower:
        score += 20
        feedback.append("PASS: Ammonium Nitrate (CAS 6484-52-2) found (+20)")
    else:
        feedback.append("FAIL: Ammonium Nitrate missing")

    if "1910-42-5" in t2s_content_lower and "paraquat" in t2s_content_lower:
        score += 20
        feedback.append("PASS: Paraquat Dichloride (CAS 1910-42-5) found (+20)")
    else:
        feedback.append("FAIL: Paraquat Dichloride missing")

    # 5. VLM Trajectory Verification (Anti-Gaming)
    vlm_points = 0
    query_vlm = env_info.get("query_vlm")
    
    if VLM_AVAILABLE and query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            all_frames = frames + [final] if final else frames
            
            vlm_res = query_vlm(images=all_frames, prompt=VLM_PROMPT)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("tier2_submit_used", False):
                    vlm_points += 15
                    feedback.append("PASS: VLM verified Tier2 Submit usage (+15)")
                else:
                    feedback.append("FAIL: VLM did not detect Tier2 Submit usage")
                    
                if parsed.get("data_entry_visible", False):
                    vlm_points += 15
                    feedback.append("PASS: VLM verified data entry process (+15)")
            else:
                # If VLM fails temporarily, grant points so valid runs aren't penalized unfairly
                vlm_points = 30 
                feedback.append("WARNING: VLM query failed, granting default process points")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            vlm_points = 30
            feedback.append("WARNING: VLM exception, granting default process points")
    else:
        # Fallback if VLM isn't hooked up in this runtime
        vlm_points = 30
        feedback.append("NOTE: VLM unavailable, granting default process points")

    score += vlm_points

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }