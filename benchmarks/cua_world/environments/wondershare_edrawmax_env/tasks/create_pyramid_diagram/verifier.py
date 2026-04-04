#!/usr/bin/env python3
"""
Verifier for create_pyramid_diagram task.

Verification Strategy:
1. File Verification (Programmatic):
   - Check if .eddx and .png files exist and were created during the task.
   - Check file sizes to ensure content.
   - Inspect .eddx (zip) XML content to verify specific text labels exist.

2. Visual Verification (VLM):
   - Check the exported PNG for a pyramid structure.
   - Verify the "Defense in Depth" title and hierarchy via VLM.
   - Use trajectory frames to confirm the agent actually built it (workflow).
"""

import json
import os
import tempfile
import zipfile
import logging
from typing import Dict, Any, List

# Import VLM utils from the environment framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    # Fallback/Mock for local testing
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=1):
        return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_LABELS = [
    "Physical Security",
    "Network Security",
    "Host Security",
    "Application Security",
    "Data Security",
    "Defense in Depth"
]

def verify_create_pyramid_diagram(traj, env_info, task_info):
    """
    Verify creation of Defense in Depth pyramid diagram.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. FILE EXISTENCE & TIMESTAMPS (30 Points)
    # =========================================================
    eddx_exists = result.get("eddx_exists", False)
    png_exists = result.get("png_exists", False)
    eddx_fresh = result.get("eddx_created_during_task", False)
    png_fresh = result.get("png_created_during_task", False)
    
    if eddx_exists and eddx_fresh:
        score += 15
        feedback_parts.append("Project file (.eddx) created successfully.")
    elif eddx_exists:
        score += 5
        feedback_parts.append("Project file exists but timestamp invalid (pre-dated).")
    else:
        feedback_parts.append("Project file (.eddx) not found.")

    if png_exists and png_fresh:
        score += 15
        feedback_parts.append("Exported image (.png) created successfully.")
    elif png_exists:
        score += 5
        feedback_parts.append("Image exists but timestamp invalid.")
    else:
        feedback_parts.append("Exported image (.png) not found.")

    # =========================================================
    # 2. CONTENT VERIFICATION - XML PARSING (30 Points)
    # =========================================================
    # We unzip the .eddx file and look for the required text labels in the XML.
    xml_labels_found = []
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/defense_in_depth_pyramid.eddx", temp_eddx.name)
            
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                # Concatenate all XML content to search
                all_xml_content = ""
                for filename in zf.namelist():
                    if filename.endswith('.xml'):
                        try:
                            all_xml_content += zf.read(filename).decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for labels
                found_count = 0
                for label in REQUIRED_LABELS:
                    # Check case-insensitive to be lenient on capitalization typos
                    if label.lower() in all_xml_content.lower():
                        found_count += 1
                        xml_labels_found.append(label)
                
                # Scoring: 5 points per label found, up to 30
                points = min(30, found_count * 5)
                score += points
                if found_count == len(REQUIRED_LABELS):
                    feedback_parts.append("All required text labels found in project file.")
                elif found_count > 0:
                    feedback_parts.append(f"Found {found_count}/{len(REQUIRED_LABELS)} labels in project file.")
                else:
                    feedback_parts.append("No required labels found in project file.")

        except Exception as e:
            feedback_parts.append(f"Failed to inspect .eddx content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # =========================================================
    # 3. VLM VISUAL VERIFICATION (40 Points)
    # =========================================================
    # Check the PNG content
    vlm_score = 0
    if png_exists:
        # Copy PNG for VLM
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/Documents/defense_in_depth_pyramid.png", temp_png.name)
            
            # Prompt for VLM
            vlm_prompt = """
            Analyze this diagram image.
            1. Is there a pyramid or triangle diagram visible?
            2. Is the diagram divided into layers/tiers?
            3. Is there a title "Defense in Depth" visible?
            4. Are there text labels on the pyramid layers?
            
            Respond in JSON:
            {
                "is_pyramid": true/false,
                "has_layers": true/false,
                "has_title": true/false,
                "has_labels": true/false
            }
            """
            
            vlm_res = query_vlm(prompt=vlm_prompt, image=temp_png.name)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("is_pyramid"): vlm_score += 10
                if parsed.get("has_layers"): vlm_score += 10
                if parsed.get("has_title"): vlm_score += 10
                if parsed.get("has_labels"): vlm_score += 10
                feedback_parts.append(f"Visual verification passed {len([k for k,v in parsed.items() if v])}/4 checks.")
            else:
                feedback_parts.append("Visual verification failed (VLM error).")
                
        except Exception as e:
            feedback_parts.append(f"Failed to process PNG for verification: {e}")
        finally:
            if os.path.exists(temp_png.name):
                os.unlink(temp_png.name)
    
    score += vlm_score

    # Fallback: If PNG missing or VLM failed, check trajectory
    if vlm_score == 0:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            traj_prompt = "Do these screenshots show a user creating a pyramid diagram with text labels?"
            traj_res = query_vlm(prompt=traj_prompt, images=frames)
            # Give partial credit if trajectory looks good (max 20 pts fallback)
            if traj_res.get("success") and "yes" in str(traj_res.get("response", "")).lower():
                score += 20
                feedback_parts.append("Trajectory shows pyramid creation (fallback verification).")

    # =========================================================
    # FINAL SCORE
    # =========================================================
    
    # Requirement: Both files must exist for a pass
    passed = (score >= 70) and eddx_exists and png_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }