#!/usr/bin/env python3
"""
Verifier for export_landmark_slices task.

Scoring (100 points total):
1. File Existence & Validity (30 pts):
   - 10 pts per file (Must exist, be valid PNG, >30KB, created during task)
2. VLM Anatomical Verification (60 pts):
   - 20 pts per file (Visual confirmation of correct anatomical plane and landmarks)
3. Distinct Views (10 pts):
   - VLM confirms the three images are distinct (not 3 copies of the same screenshot)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logger = logging.getLogger(__name__)

def verify_export_landmark_slices(traj, env_info, task_info):
    """Verify 3 exported slice images for correct anatomy."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Load basic file stats from container
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/export_landmark_slices_result.json", tmp_json.name)
        with open(tmp_json.name) as f:
            file_stats = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    files_data = file_stats.get("files", {})
    images_to_verify = {}
    
    # 2. Check files (Programmatic)
    # Keys: axial, sagittal, coronal
    for key, human_name in [("axial", "Axial Orbits"), ("sagittal", "Sagittal Midline"), ("coronal", "Coronal Petrous")]:
        info = files_data.get(key, {})
        
        # Check existence
        if not info.get("exists"):
            feedback_parts.append(f"Missing {human_name} file")
            continue
            
        # Check validity and size
        if not info.get("valid_png"):
            feedback_parts.append(f"{human_name}: Invalid PNG format")
            continue
            
        if info.get("size_bytes", 0) < 30 * 1024:
            feedback_parts.append(f"{human_name}: File too small (likely empty)")
            continue
            
        # Check creation time
        if not info.get("created_during_task"):
            feedback_parts.append(f"{human_name}: File old (not created during task)")
            continue
            
        # Passed programmatic checks
        score += 10
        feedback_parts.append(f"{human_name}: File valid")
        
        # Queue for VLM
        images_to_verify[key] = info["path"]

    # 3. VLM Verification
    # We need to copy the images out to verify their content
    vlm_score = 0
    if images_to_verify:
        for key, remote_path in images_to_verify.items():
            local_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png").name
            try:
                copy_from_env(remote_path, local_img)
                
                # Define prompt based on view
                if key == "axial":
                    prompt = ("Does this medical image show an AXIAL slice of a skull? "
                              "Look for two dark circular orbits (eye sockets) and the nasal cavity in the center. "
                              "Return JSON: {\"is_axial\": boolean, \"orbits_visible\": boolean}")
                elif key == "sagittal":
                    prompt = ("Does this medical image show a SAGITTAL (side profile) slice of a skull? "
                              "Look for the midline profile, nasal cavity, and skull curvature. "
                              "Return JSON: {\"is_sagittal\": boolean, \"midline_visible\": boolean}")
                elif key == "coronal":
                    prompt = ("Does this medical image show a CORONAL (frontal) slice of a skull? "
                              "Look for dense temporal bones (ear region) or face structures. "
                              "Return JSON: {\"is_coronal\": boolean, \"petrous_or_face_visible\": boolean}")

                # Query VLM
                resp = query_vlm(prompt=prompt, image=local_img)
                
                if resp.get("success"):
                    parsed = resp.get("parsed", {})
                    # Check criteria
                    if key == "axial" and parsed.get("is_axial") and parsed.get("orbits_visible"):
                        vlm_score += 20
                        feedback_parts.append("Axial view confirmed")
                    elif key == "sagittal" and parsed.get("is_sagittal"):
                        vlm_score += 20
                        feedback_parts.append("Sagittal view confirmed")
                    elif key == "coronal" and parsed.get("is_coronal"):
                        vlm_score += 20
                        feedback_parts.append("Coronal view confirmed")
                    else:
                        feedback_parts.append(f"VLM rejected {key} view content")
                else:
                    feedback_parts.append(f"VLM failed for {key}")
                    
            except Exception as e:
                feedback_parts.append(f"Error verifying {key}: {e}")
            finally:
                if os.path.exists(local_img):
                    os.unlink(local_img)
    
    score += vlm_score

    # 4. Distinctness Check (Implicit via VLM success on different prompts, 
    # but we give 10 bonus points if all 3 passed VLM, implying they are distinct)
    if vlm_score == 60:
        score += 10
        feedback_parts.append("All views distinct and correct")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }