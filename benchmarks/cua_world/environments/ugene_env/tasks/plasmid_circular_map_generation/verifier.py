#!/usr/bin/env python3
"""Verifier for plasmid_circular_map_generation task.

Verification Strategy:
1. Programmatic Checks:
   - Exported PNG file exists, was created during the task, and has sufficient resolution (e.g. >500x500).
   - Text report exists, created during task.
   - Coordinate accuracy parsed from text report (EcoRI ~396, BamHI ~417, HindIII ~447).
2. VLM Checks:
   - Trajectory Check: Did the agent interact with Restriction Sites and Circular Viewer?
   - Content Check: Does the final image actually resemble a circular plasmid map with relevant labels?
"""

import os
import json
import base64
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_content(b64_content):
    """Decodes base64 content and returns lowercased string."""
    if not b64_content:
        return ""
    try:
        decoded_bytes = base64.b64decode(b64_content)
        return decoded_bytes.decode('utf-8', errors='ignore').lower()
    except Exception as e:
        logger.error(f"Failed to decode base64 report: {e}")
        return ""

def extract_all_numbers(text):
    """Extracts all integer sequences from the text."""
    return [int(x) for x in re.findall(r'\b\d+\b', text)]

def check_coordinates(text, expected_ecori, expected_bamhi, expected_hindiii, tolerance):
    """Checks if the expected coordinates (± tolerance) are present in the text."""
    numbers = extract_all_numbers(text)
    
    def has_coord(expected):
        return any(abs(n - expected) <= tolerance for n in numbers)
    
    ecori_found = has_coord(expected_ecori)
    bamhi_found = has_coord(expected_bamhi)
    hindiii_found = has_coord(expected_hindiii)
    
    return ecori_found, bamhi_found, hindiii_found

def build_vlm_prompt():
    return """You are verifying if a bioinformatics agent successfully created a customized circular plasmid map.

Look at the trajectory screenshots and the final exported image. Determine the following:
1. Did the agent use the restriction site finding tool to locate EcoRI, BamHI, and HindIII?
2. Did the agent open or switch to the 'Circular Viewer' representation of the sequence?
3. Does the final exported image (or the final state screenshot) show a circular DNA map diagram?
4. Can you see enzyme labels like "EcoRI", "BamHI", and "HindIII" visibly marked on the circular map?
5. Can you see standard CDS features (like 'bla', 'AmpR', or 'lacZ') marked on the circular map?

Respond in JSON format exactly like this:
{
    "used_restriction_tool": true/false,
    "opened_circular_viewer": true/false,
    "shows_circular_map": true/false,
    "shows_enzyme_labels": true/false,
    "shows_cds_features": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_plasmid_circular_map(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env not available."}
    
    metadata = task_info.get('metadata', {})
    expected_ecori = metadata.get('expected_ecori_pos', 396)
    expected_bamhi = metadata.get('expected_bamhi_pos', 417)
    expected_hindiii = metadata.get('expected_hindiii_pos', 447)
    tolerance = metadata.get('coordinate_tolerance', 5)

    # 1. Read programmatic results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_result.close()
    
    try:
        copy_from_env("/tmp/plasmid_circular_map_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON: {e}. Agent likely did not complete the task."
        }
        
    # --- Criterion 1: Map Image Exists & Validity (25 points max) ---
    c1 = 0
    if result.get("image_exists", False):
        if result.get("image_created_during_task", False):
            c1 += 15
            feedback_parts.append("Map image created (+15)")
            
            w = result.get("image_width", 0)
            h = result.get("image_height", 0)
            if w >= 500 and h >= 500:
                c1 += 10
                feedback_parts.append(f"Image resolution is sufficient ({w}x{h}) (+10)")
            elif w > 0 and h > 0:
                c1 += 5
                feedback_parts.append(f"Image resolution is low ({w}x{h}) (+5)")
        else:
            feedback_parts.append("Image file exists but was NOT created during task (0)")
    else:
        feedback_parts.append("Map image MISSING (0)")
    score += c1
    
    # --- Criterion 2: Map Details Report Exists (15 points max) ---
    c2 = 0
    report_content = ""
    if result.get("report_exists", False):
        if result.get("report_created_during_task", False):
            c2 += 15
            feedback_parts.append("Details report created (+15)")
            report_content = parse_report_content(result.get("report_content_b64", ""))
        else:
            feedback_parts.append("Details report exists but was NOT created during task (0)")
    else:
        feedback_parts.append("Details report MISSING (0)")
    score += c2
    
    # --- Criterion 3: Coordinate Accuracy (20 points max) ---
    c3 = 0
    if report_content:
        mentions_enzymes = all(e in report_content for e in ['eco', 'bam', 'hind'])
        if mentions_enzymes:
            feedback_parts.append("Report mentions all three enzymes")
            
        ecori_ok, bamhi_ok, hindiii_ok = check_coordinates(
            report_content, expected_ecori, expected_bamhi, expected_hindiii, tolerance
        )
        
        correct_coords = sum([ecori_ok, bamhi_ok, hindiii_ok])
        
        if correct_coords == 3:
            c3 = 20
            feedback_parts.append("All 3 enzyme coordinates accurate (+20)")
        elif correct_coords > 0:
            c3 = correct_coords * 6
            feedback_parts.append(f"{correct_coords}/3 enzyme coordinates accurate (+{c3})")
        else:
            feedback_parts.append("No accurate coordinates found in report (0)")
    score += c3

    # --- Criteria 4 & 5: VLM Hybrid Verification (40 points max) ---
    c4_5 = 0
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images_to_send = frames
    if final:
        images_to_send.append(final)
        
    # Default VLM checks
    vlm_passed = False
    if images_to_send:
        vlm_result = query_vlm(images=images_to_send, prompt=build_vlm_prompt())
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            vlm_score = 0
            if parsed.get("used_restriction_tool", False): vlm_score += 10
            if parsed.get("opened_circular_viewer", False): vlm_score += 10
            if parsed.get("shows_circular_map", False): vlm_score += 10
            if parsed.get("shows_enzyme_labels", False): vlm_score += 5
            if parsed.get("shows_cds_features", False): vlm_score += 5
            
            c4_5 = vlm_score
            feedback_parts.append(f"VLM Visual Verification (+{c4_5}/40)")
            
            if parsed.get("shows_circular_map") and parsed.get("opened_circular_viewer"):
                vlm_passed = True
        else:
            feedback_parts.append("VLM verification failed to run")
    else:
        feedback_parts.append("No screenshots available for VLM verification")
        
    score += c4_5
    
    # Final pass conditions: Must have created the image AND passed VLM circular map detection
    key_criteria_met = (result.get("image_created_during_task", False) and vlm_passed)
    passed = (score >= 70) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }