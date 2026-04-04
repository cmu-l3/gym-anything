#!/usr/bin/env python3
"""
Verifier for create_stakeholder_matrix task.

Verification Strategy:
1. File Checks: .eddx and .png must exist and be created during the task.
2. Content Check: .eddx (ZIP) extracted to verify required text labels exist in XML.
3. VLM Verification: Analyzes the final screenshot/exported PNG to verify 2x2 layout and stakeholder positioning.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_STRINGS = [
    "Interest", "Power",
    "Manage Closely", "Keep Satisfied", "Keep Informed", "Monitor",
    "Chief Medical Officer", "Finance Director", "Nursing Staff", "IT Maintenance Team", "Hospital Board"
]

VLM_PROMPT = """
You are verifying a "Stakeholder Power/Interest Matrix" created in diagramming software.
The diagram should be a 2x2 grid with axes "Power" (Y) and "Interest" (X).

Check for the following:
1. Is there a 2x2 matrix/grid visible?
2. Are the quadrants labeled roughly as:
   - Top-Right: Manage Closely
   - Top-Left: Keep Satisfied
   - Bottom-Right: Keep Informed
   - Bottom-Left: Monitor
3. Are the stakeholders positioned correctly?
   - "Chief Medical Officer" and "Hospital Board" should be in the Top-Right (High Power, High Interest).
   - "Finance Director" should be in the Top-Left (High Power, Low Interest).
   - "Nursing Staff" should be in the Bottom-Right (Low Power, High Interest).
   - "IT Maintenance Team" should be in the Bottom-Left (Low Power, Low Interest).

Respond with JSON:
{
  "grid_visible": true/false,
  "quadrants_labeled": true/false,
  "stakeholders_plotted": true/false,
  "positioning_correct": true/false,
  "feedback": "Explain what is correct or incorrect based on the positions you see."
}
"""

def verify_create_stakeholder_matrix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. File Existence & Timestamp Checks (40 points)
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_created = result_data.get('eddx_created_during_task', False)
    png_exists = result_data.get('png_exists', False)
    
    if eddx_exists and eddx_created:
        score += 20
        feedback_parts.append(".eddx file created")
    elif eddx_exists:
        score += 5
        feedback_parts.append(".eddx file exists but timestamp invalid")
    else:
        feedback_parts.append(".eddx file missing")

    if png_exists and result_data.get('png_created_during_task', False):
        score += 20
        feedback_parts.append(".png file created")
    else:
        feedback_parts.append(".png file missing/invalid")

    # 3. Content Verification (Text in EDDX) (30 points)
    # Only possible if EDDX exists
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(task_info['metadata']['expected_eddx_path'], temp_eddx.name)
            
            found_strings = 0
            total_strings = len(REQUIRED_STRINGS)
            
            # EdrawMax .eddx is a zip; text is usually in pages/pageX.xml or similar
            is_valid_zip = False
            try:
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    is_valid_zip = True
                    # Read all XML content
                    all_content = ""
                    for name in zf.namelist():
                        if name.endswith('.xml') or name.endswith('.json'):
                            try:
                                all_content += zf.read(name).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for required strings
                    missing = []
                    for s in REQUIRED_STRINGS:
                        if s in all_content:
                            found_strings += 1
                        else:
                            missing.append(s)
                            
            except zipfile.BadZipFile:
                feedback_parts.append("EDDX is not a valid zip archive")

            if is_valid_zip:
                # Calculate text score
                text_score = (found_strings / total_strings) * 30
                score += int(text_score)
                if len(missing) == 0:
                    feedback_parts.append("All text labels found")
                else:
                    feedback_parts.append(f"Missing text labels: {', '.join(missing[:3])}...")

        except Exception as e:
            feedback_parts.append(f"Content check failed: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # 4. VLM Verification (30 points)
    # We use the exported PNG if available (clearer), otherwise final screenshot
    vlm_image_source = "screenshot"
    image_to_check = get_final_screenshot(traj)
    
    # If the agent exported a PNG, let's try to verify that (it's the direct artifact)
    # However, retrieving it requires copy_from_env. Let's stick to the framework's screenshot
    # for simplicity and robustness, as we already have get_final_screenshot.
    
    if image_to_check:
        vlm_res = query_vlm(prompt=VLM_PROMPT, image=image_to_check)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            vlm_feedback = parsed.get('feedback', '')
            
            if parsed.get('grid_visible'):
                score += 5
            if parsed.get('quadrants_labeled'):
                score += 5
            if parsed.get('positioning_correct'):
                score += 20
                feedback_parts.append("VLM confirms correct stakeholder placement")
            else:
                feedback_parts.append(f"VLM positioning check: {vlm_feedback}")
        else:
            feedback_parts.append("VLM analysis failed")
    else:
        feedback_parts.append("No screenshot available for VLM")

    # Final scoring logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }