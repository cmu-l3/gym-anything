#!/usr/bin/env python3
"""
Verifier for the annotate_finding task in Weasis.
"""

import os
import json
import tempfile
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Safe fallback if gym_anything framework isn't directly importable
    def get_final_screenshot(traj):
        if not traj: return None
        return traj[-1].get("observation", {}).get("image")

    def sample_trajectory_frames(traj, n=5):
        if not traj: return []
        step = max(1, len(traj) // n)
        return [t.get("observation", {}).get("image") for t in traj[::step]]

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_ANNOTATION_PROMPT = """You are verifying a medical image viewer workflow.
Look at this sequence of screenshots from the agent interacting with Weasis.

We are looking for evidence that the agent actively used the annotation tools:
1. Did the agent draw an ARROW pointing to a structure on the medical image?
2. Did the agent place a TEXT label somewhere on the image that says exactly or very similarly: "Suspected lesion"?
3. Are these annotations (the arrow and the text) visible on top of the medical scan?

Respond in JSON format:
{
    "arrow_visible": true/false,
    "text_visible": true/false,
    "text_matches_expected": true/false,
    "annotations_on_scan": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_annotate_finding(traj, env_info, task_info):
    """
    Verify that the user annotated the DICOM image and exported it correctly.
    Uses file metadata checks (anti-gaming) and VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env function missing"}

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Programmatic File Checks
    # -------------------------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check 1: File Existence (15 pts)
    file_exists = result.get('file_exists', False)
    if file_exists:
        score += 15
        feedback_parts.append("Exported file exists")
    else:
        feedback_parts.append("Exported file NOT found")
        # Early return - cannot pass without exporting the file
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check 2: Valid format & size > 10KB (10 pts)
    valid_jpeg = result.get('valid_jpeg', False)
    file_size = result.get('file_size_bytes', 0)
    
    if valid_jpeg and file_size > 10000:
        score += 10
        feedback_parts.append(f"Valid JPEG ({file_size // 1024} KB)")
    elif valid_jpeg:
        score += 5
        feedback_parts.append(f"JPEG valid but suspiciously small ({file_size} bytes)")
    else:
        feedback_parts.append("File exists but is NOT a valid JPEG")

    # Check 3: Timestamps (15 pts) -> Anti-gaming check
    created_during_task = result.get('created_during_task', False)
    if created_during_task:
        score += 15
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("File timestamp violation (possible pre-staged file)")

    # -------------------------------------------------------------------------
    # 2. VLM Trajectory Checks
    # -------------------------------------------------------------------------
    vlm_success = False
    if query_vlm and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
            
            # Remove None values
            frames = [f for f in frames if f is not None]

            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt=VLM_ANNOTATION_PROMPT
                )
                
                if vlm_result and vlm_result.get('success') and 'parsed' in vlm_result:
                    parsed = vlm_result['parsed']
                    vlm_success = True
                    
                    # Arrow visible (20 pts)
                    if parsed.get('arrow_visible', False):
                        score += 20
                        feedback_parts.append("VLM: Arrow detected")
                    else:
                        feedback_parts.append("VLM: Arrow NOT detected")
                        
                    # Text annotation visible & matches (20 pts)
                    if parsed.get('text_visible', False) and parsed.get('text_matches_expected', False):
                        score += 20
                        feedback_parts.append("VLM: Text 'Suspected lesion' detected")
                    elif parsed.get('text_visible', False):
                        score += 10
                        feedback_parts.append("VLM: Some text detected but mismatched")
                    else:
                        feedback_parts.append("VLM: Text annotation NOT detected")
                        
                    # Placement context (20 pts)
                    if parsed.get('annotations_on_scan', False):
                        score += 20
                        feedback_parts.append("VLM: Annotations properly placed on scan")
                        
                else:
                    feedback_parts.append("VLM query returned invalid format")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append(f"VLM check failed: {str(e)}")
            
    if not vlm_success:
        feedback_parts.append("Could not perform visual verification")

    # Final scoring evaluation
    # To pass, they must have exported a valid file during the task, AND have visual evidence
    passed = (score >= 60) and created_during_task and file_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }