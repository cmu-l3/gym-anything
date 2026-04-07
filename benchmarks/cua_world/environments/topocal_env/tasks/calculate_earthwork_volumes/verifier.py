#!/usr/bin/env python3
"""
Verifier for the TopoCal Calculate Earthwork Volumes task.

This verifier checks:
1. Did the agent create the report text file?
2. Did the agent calculate and record the correct cut/fill volumes (within tolerance)?
3. Are the math mechanics internally consistent (Net = Cut - Fill)?
4. Did the agent actually use TopoCal to process the surfaces (VLM verification)?
5. Did the agent save the TopoCal project file?
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a CAD earthwork calculation task in TopoCal.
Review these trajectory frames from the user's session.
Did the user accomplish the following?
1. Successfully loaded BOTH point clouds (existing ground and proposed grade)?
2. Generated triangulated terrain meshes (TIN / MDT) visible in the viewport?
3. Opened the volume computation tool or displayed a dialogue showing computed volumes?

Respond with a JSON object:
{
    "surfaces_visible": true/false,
    "volume_dialog_used": true/false
}
"""

def parse_volume(text, keyword):
    """Safely extract float volume from strings like 'Cut: 14400.0 m3'"""
    # Look for keyword followed by optional colon/equals, spaces, and numbers/commas/decimals
    pattern = re.compile(rf'(?i){keyword}\s*[:=]?\s*([\d\.,]+)')
    match = pattern.search(text)
    if match:
        val_str = match.group(1).replace(',', '')  # remove thousands separators if any
        try:
            return float(val_str)
        except ValueError:
            return None
    return None

def verify_calculate_earthwork_volumes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    # Extract metadata targets
    metadata = task_info.get('metadata', {})
    expected_cut = metadata.get('expected_cut_m3', 14400.0)
    expected_fill = metadata.get('expected_fill_m3', 1600.0)
    tolerance_pct = metadata.get('volume_tolerance_percent', 15) / 100.0
    
    score = 0
    feedback_parts = []
    
    # --- 1. Programmatic Verification ---
    # Retrieve the exported JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or read task_result.json: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Evaluate Report File
    report_exists = result.get('report_exists', False)
    content = result.get('report_content', '')
    project_saved = result.get('project_saved', False)
    
    if project_saved:
        score += 10
        feedback_parts.append("✅ TopoCal project saved")
    else:
        feedback_parts.append("❌ TopoCal project not saved")

    if not report_exists:
        feedback_parts.append("❌ Report file (earthwork_report.txt) not found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    score += 10
    feedback_parts.append("✅ Report file created")
    
    # Parse Volumes
    cut_val = parse_volume(content, "Cut")
    fill_val = parse_volume(content, "Fill")
    net_val = parse_volume(content, "Net")
    
    math_valid = False
    vol_points = 0
    
    if cut_val is not None and fill_val is not None:
        # Check tolerance ranges
        cut_diff = abs(cut_val - expected_cut) / expected_cut
        fill_diff = abs(fill_val - expected_fill) / expected_fill
        
        if cut_diff <= tolerance_pct:
            vol_points += 20
            feedback_parts.append(f"✅ Cut volume accurate ({cut_val} m3)")
        else:
            feedback_parts.append(f"❌ Cut volume {cut_val} outside {tolerance_pct*100}% tolerance (Expected: ~{expected_cut})")
            
        if fill_diff <= tolerance_pct:
            vol_points += 20
            feedback_parts.append(f"✅ Fill volume accurate ({fill_val} m3)")
        else:
            feedback_parts.append(f"❌ Fill volume {fill_val} outside {tolerance_pct*100}% tolerance (Expected: ~{expected_fill})")

        # Internal consistency check: Net = Cut - Fill (Allowing small float/rounding discrepancies)
        if net_val is not None:
            expected_net = abs(cut_val - fill_val) # Some software outputs net as absolute
            actual_net = abs(net_val)
            if abs(actual_net - expected_net) <= 5.0:
                vol_points += 10
                math_valid = True
                feedback_parts.append("✅ Net volume is internally consistent")
            else:
                feedback_parts.append(f"❌ Net volume math incorrect. {cut_val} - {fill_val} != {net_val}")
    else:
        feedback_parts.append("❌ Could not parse numerical values for Cut and Fill from report.")
        
    score += vol_points

    # --- 2. VLM Trajectory Verification ---
    vlm_points = 0
    if query_vlm and 'sample_trajectory_frames' in env_info:
        frames = env_info['sample_trajectory_frames'](traj, n=5)
        if frames:
            try:
                vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
                vlm_data = vlm_resp.get("parsed", {})
                
                if vlm_data.get("surfaces_visible", False):
                    vlm_points += 15
                    feedback_parts.append("✅ VLM: TIN surfaces identified")
                else:
                    feedback_parts.append("❌ VLM: Surfaces not identified")
                    
                if vlm_data.get("volume_dialog_used", False):
                    vlm_points += 15
                    feedback_parts.append("✅ VLM: Volume dialog accessed")
                else:
                    feedback_parts.append("❌ VLM: Volume computation dialog not seen")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                
    score += vlm_points

    # Final pass evaluation
    # To pass, they must score >= 60, report file must exist, and at least ONE volume must be right
    volumes_acceptable = vol_points >= 20
    passed = (score >= 60) and report_exists and volumes_acceptable

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }