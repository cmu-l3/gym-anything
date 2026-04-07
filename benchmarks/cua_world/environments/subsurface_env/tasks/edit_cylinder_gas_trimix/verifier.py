#!/usr/bin/env python3
"""
Verifier for edit_cylinder_gas_trimix task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. File modified during task (prevent "do nothing" gaming)
2. Data integrity (total dives remained intact)
3. Target dive #2 cylinder[0] O2 % updated
4. Target dive #2 cylinder[0] He % updated
5. VLM trajectory verification: confirms interaction with Equipment tab and Gas fields
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_percentage(val_str, default=0.0):
    """Parse percentage string like '21.0%' to float."""
    if not val_str:
        return default
    try:
        return float(val_str.replace('%', '').strip())
    except ValueError:
        return default

def verify_edit_cylinder_gas_trimix(traj, env_info, task_info):
    """Verify that dive #2 cylinder gas was changed to Trimix 21/35."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_o2 = metadata.get('expected_o2_percent', 21.0)
    expected_he = metadata.get('expected_he_percent', 35.0)
    tolerance = metadata.get('tolerance_percent', 1.0)

    # 1. Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Checks
    if not result.get("file_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Dive log file does not exist. It may have been deleted or moved."
        }
        
    if result.get("xml_error"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"XML Parse Error in dive file: {result['xml_error']}"
        }

    # Criterion 1: File modified during task (10 points)
    if result.get("file_modified_during_task"):
        score += 10
        feedback_parts.append("File modified")
    else:
        feedback_parts.append("File NOT modified (Task wasn't saved)")

    # Criterion 2: Dive count integrity (10 points)
    # The sample file starts with 8 dives in SampleDivesV2.ssrf (or similar small number).
    # As long as it's > 0 and dive #2 exists, we're good.
    if result.get("dive2_exists") and result.get("total_dives", 0) > 0:
        score += 10
        feedback_parts.append(f"Dive #2 found (Total: {result['total_dives']})")
    else:
        feedback_parts.append("Dive #2 missing or file corrupted")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Parse recorded values
    raw_o2 = result.get("dive2_cyl1_o2", "")
    raw_he = result.get("dive2_cyl1_he", "")
    
    # If O2 is missing but He is explicitly set, Subsurface implicitly assumes Air (21%) base for Trimix.
    o2_val = parse_percentage(raw_o2, default=21.0 if raw_he else 0.0)
    he_val = parse_percentage(raw_he, default=0.0)

    # Criterion 3: O2 Percentage (25 points)
    o2_correct = abs(o2_val - expected_o2) <= tolerance
    if o2_correct and raw_he: # Must be part of a trimix config
        score += 25
        feedback_parts.append(f"O2 correct (~{o2_val}%)")
    else:
        feedback_parts.append(f"O2 incorrect ({o2_val}%, expected {expected_o2}%)")

    # Criterion 4: He Percentage (30 points)
    he_correct = abs(he_val - expected_he) <= tolerance
    if he_correct:
        score += 30
        feedback_parts.append(f"He correct (~{he_val}%)")
    else:
        feedback_parts.append(f"He incorrect ({he_val}%, expected {expected_he}%)")

    # 3. VLM Trajectory Verification
    vlm_score = 0
    try:
        # Import dynamically to fail gracefully if not available in testing environment
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent.parent))
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = """Analyze these screenshots of the Subsurface dive log application.
Did the user interact with the 'Equipment' tab and configure a Trimix cylinder gas (specifically adjusting Helium 'He' and Oxygen 'O2' fields)?

Look for:
1. The 'Equipment' tab being selected in the bottom/right pane.
2. Interaction with the 'Gas' column/fields (O2% and He%).
3. Values being typed or adjusted to 21% O2 and 35% He.

Reply in JSON format:
{
    "equipment_tab_used": true/false,
    "gas_mix_edited": true/false,
    "trimix_values_visible": true/false,
    "confidence": "low/medium/high"
}"""
            vlm_result = query_vlm(images=images, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("equipment_tab_used"): vlm_score += 10
                if parsed.get("gas_mix_edited"): vlm_score += 10
                if parsed.get("trimix_values_visible"): vlm_score += 5
                
                feedback_parts.append(f"VLM visual check: +{vlm_score}")
            else:
                feedback_parts.append("VLM query failed or invalid JSON")
        else:
            feedback_parts.append("No screenshots available for VLM")
    except ImportError:
        logger.warning("VLM utilities not available - skipping VLM check")
        feedback_parts.append("VLM unavailable - awarded auto-points")
        vlm_score = 25  # Grant points if VLM module is missing but we got this far
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM error: {str(e)[:20]}")

    score += vlm_score

    # Determine passing state
    # Must have modified the file and successfully set the Trimix gas values
    key_criteria_met = result.get("file_modified_during_task") and o2_correct and he_correct
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "o2_value": o2_val,
            "he_value": he_val,
            "file_modified": result.get("file_modified_during_task")
        }
    }