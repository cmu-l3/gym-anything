#!/usr/bin/env python3
"""
Verifier for Gas/Vapor Detection Profile Compilation task.

VERIFICATION STRATEGY:
1. File Existence & Authenticity:
   - Checks if output file exists and was created during the task.
   - Checks file size > 300 bytes (prevents empty/trivial files).

2. Content Accuracy (Programmatic):
   - Decodes the text report.
   - For each of the 6 chemicals, looks for key terms related to:
     - Color (e.g., Chlorine -> "green" or "yellow")
     - Odor (e.g., H2S -> "rotten egg")
     - Vapor Density (e.g., Ammonia -> "lighter")
     - Warning Assessment (Logic check: CO -> "No", H2S -> "No" due to fatigue).

3. Workflow Verification (VLM):
   - Uses VLM to check trajectory frames.
   - Verifies the agent actually visited CAMEO Chemicals and looked up data.

SCORING:
- File created: 5 pts
- All chemicals present: 10 pts
- Per-chemical accuracy: ~12-15 pts each (Total 81 pts)
- VLM Trajectory check: 4 pts
"""

import json
import base64
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gas_detection_profile(traj, env_info, task_info):
    """
    Verify the gas detection profile report.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Base checks
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    content_b64 = result.get('output_content_b64', "")
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if not created_during:
        return {"passed": False, "score": 0, "feedback": "Report file was not created during the task session."}

    # Decode content
    try:
        report_text = base64.b64decode(content_b64).decode('utf-8', errors='ignore').lower()
    except Exception:
        return {"passed": False, "score": 5, "feedback": "Failed to decode report content."}

    if len(report_text) < 300:
        return {"passed": False, "score": 5, "feedback": "Report content is too short to be valid."}

    score = 5  # Base points for valid file
    feedback = ["File created successfully."]
    
    # Get ground truth
    ground_truth = task_info.get('metadata', {}).get('ground_truth', {})
    
    # Check coverage of all chemicals
    chemicals_found = 0
    missing_chemicals = []
    
    for chem in ground_truth.keys():
        if chem.lower() in report_text:
            chemicals_found += 1
        else:
            missing_chemicals.append(chem)
            
    if chemicals_found == 6:
        score += 10
        feedback.append("All 6 chemicals referenced.")
    else:
        score += int(chemicals_found * 1.5)
        feedback.append(f"Found {chemicals_found}/6 chemicals. Missing: {', '.join(missing_chemicals)}.")

    # Detailed Content Verification
    # We verify by checking if keywords appear in the document.
    # Note: Simple keyword search has false positive risk if formatting is messy, 
    # but demanding structured parsing is too strict for a general text file task.
    # We assume the agent writes paragraphs or sections for each chemical.
    
    # Split text into "sections" roughly by chemical name indices if possible, 
    # but for robustness, we'll check if the document *contains* the correct facts.
    
    for chem, props in ground_truth.items():
        chem_score = 0
        max_chem_score = 12 if chem in ["Chlorine", "Nitrogen Dioxide", "Ammonia"] else 15
        
        chem_name = chem.lower()
        if chem_name not in report_text:
            continue
            
        # Context window: simple approach - check if properties exist in the text.
        # A more advanced approach would try to segment the text, but let's stick to document-level 
        # presence of unique combinations or specific keywords.
        
        # Color Check
        color_match = any(c in report_text for c in props['color'])
        
        # Odor Check
        odor_match = any(o in report_text for o in props['odor'])
        
        # Density Check
        density_match = any(d in report_text for d in props['density'])
        
        # Warning Assessment Check
        # This is the most critical logic. 
        # For "No" warning chemicals (CO, H2S, Phosgene), we look for negative indicators near the chemical name 
        # or globally if the report is short.
        # To be precise without segmentation, we'll give points if the *specific reasoning keywords* appear.
        
        warning_correct = False
        if props['warning'] == 'no':
            # For H2S, looking for "fatigue" or "desensitize"
            if 'risk_keywords' in props:
                if any(k in report_text for k in props['risk_keywords']):
                    warning_correct = True
            # For CO, looking for "odorless" + "colorless" implies no warning
            elif chem == "Carbon Monoxide":
                if "odorless" in report_text and "colorless" in report_text:
                    warning_correct = True
        else:
            # For "Yes" warning (Chlorine, Ammonia), presence of "strong", "pungent", "irritating" usually implies yes
            if any(x in report_text for x in ["adequate", "yes", "sufficient", "detectable"]):
                warning_correct = True

        # Assign points
        if color_match: chem_score += 3
        if odor_match: chem_score += 3
        if density_match: chem_score += 3
        if warning_correct: chem_score += (max_chem_score - 9)
        
        score += chem_score

    # VLM Verification of Workflow (Trajectory)
    # Ensure they actually used the website
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        prompt = """
        Did the user navigate to the CAMEO Chemicals website and look up chemical datasheets?
        I am looking for evidence of:
        1. The CAMEO Chemicals homepage or search bars.
        2. Datasheet pages for chemicals like Chlorine, Carbon Monoxide, Ammonia, etc.
        3. Reading physical properties sections.
        
        Answer 'YES' or 'NO' and explain briefly.
        """
        vlm_result = query_vlm(images=frames, prompt=prompt)
        if vlm_result.get("success") and "YES" in vlm_result.get("parsed", {}).get("answer", "").upper():
            vlm_score = 4
            feedback.append("VLM confirmed CAMEO Chemicals usage.")
        elif vlm_result.get("success"):
            # Fallback parsing if JSON isn't perfect
            if "YES" in str(vlm_result).upper():
                vlm_score = 4
    
    score += vlm_score

    # Final logic checks
    # Carbon Monoxide MUST be identified as having NO adequate warning to pass high score
    co_safety_critical = "carbon monoxide" in report_text and "odorless" in report_text
    
    # H2S MUST identify olfactory fatigue risk
    h2s_safety_critical = "hydrogen sulfide" in report_text and ("fatigue" in report_text or "desensitize" in report_text or "paralyze" in report_text)
    
    if not co_safety_critical:
        feedback.append("CRITICAL: Failed to identify Carbon Monoxide as odorless/undetectable.")
    if not h2s_safety_critical:
        feedback.append("CRITICAL: Failed to identify Hydrogen Sulfide olfactory fatigue risk.")

    # Cap score at 100
    score = min(score, 100)
    
    return {
        "passed": score >= 60 and co_safety_critical,
        "score": score,
        "feedback": " ".join(feedback)
    }