#!/usr/bin/env python3
"""
Verifier for Decomposition Product Screening task.

Criteria:
1. Report file exists and was created during the task (Anti-gaming).
2. Report contains sections for all 4 required chemicals.
3. Report correctly identifies decomposition products for each chemical based on keywords.
4. Report includes CAS numbers.
5. VLM verification of trajectory (Agent actually visited CAMEO sites).
"""

import json
import base64
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_decomposition_product_screening(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    chemicals = metadata.get('chemicals', [])
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Extract report content
    report_content = ""
    if result.get('report_exists') and result.get('report_content_base64'):
        try:
            report_content = base64.b64decode(result.get('report_content_base64')).decode('utf-8', errors='ignore')
        except Exception as e:
            logger.error(f"Failed to decode report: {e}")

    # --- SCORING ---
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Anti-Gaming (10 pts)
    if not result.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file not found at expected path."}
    
    if not result.get('report_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Report file was not modified during the task (Anti-gaming check failed)."}
    
    if len(report_content) < 100:
        feedback_parts.append("Report file is too short/empty.")
        score += 0
    else:
        score += 10
        feedback_parts.append("Report file created and has content.")

    # Criterion 2 & 3: Content Accuracy (60 pts - 15 per chemical)
    # We check if the chemical name matches AND if relevant decomposition keywords are nearby.
    
    content_lower = report_content.lower()
    
    for chem in chemicals:
        chem_name = chem['name']
        chem_keywords = chem['expected_terms']
        chem_cas = chem['cas']
        
        # Check for chemical presence
        if chem_name.lower() in content_lower:
            chem_score = 5 # Base points for finding the chemical
            
            # Check for decomposition keywords
            found_keywords = [kw for kw in chem_keywords if kw.lower() in content_lower]
            if len(found_keywords) >= 1:
                chem_score += 10 # Points for finding correct data
                feedback_parts.append(f"✅ Found data for {chem_name}")
            else:
                feedback_parts.append(f"⚠️ {chem_name} found, but missing specific decomposition keywords (expected: {', '.join(chem_keywords[:2])}...)")
            
            score += chem_score
        else:
            feedback_parts.append(f"❌ {chem_name} not found in report.")

    # Criterion 4: CAS Numbers (10 pts)
    cas_count = 0
    for chem in chemicals:
        if chem['cas'] in report_content:
            cas_count += 1
    
    if cas_count >= 3:
        score += 10
        feedback_parts.append(f"✅ Included CAS numbers ({cas_count}/4)")
    elif cas_count > 0:
        score += 5
        feedback_parts.append(f"⚠️ Included some CAS numbers ({cas_count}/4)")
    else:
        feedback_parts.append("❌ Missing CAS numbers")

    # Criterion 5: VLM Trajectory Verification (20 pts)
    # We want to verify the agent actually navigated the site, not just hallucinated the text.
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    Review this sequence of screenshots from a web browsing task.
    The user is supposed to be on the CAMEO Chemicals website looking up hazardous chemicals.
    
    1. Do you see the CAMEO Chemicals website interface (blue header, NOAA logo)?
    2. Do you see search results or datasheets for any of these chemicals: Sodium Azide, Carbon Disulfide, Methyl Isocyanate, Phosphorus Trichloride?
    3. Do you see a section labeled "Reactivity Profile" or "Decomposition"?
    
    Return JSON: {"cameo_visible": bool, "chemicals_searched": bool, "reactivity_section_seen": bool}
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('cameo_visible', False):
            vlm_score += 5
        if parsed.get('chemicals_searched', False):
            vlm_score += 10
        if parsed.get('reactivity_section_seen', False):
            vlm_score += 5
            
        score += vlm_score
        if vlm_score < 10:
             feedback_parts.append("⚠️ VLM did not clearly see CAMEO navigation or chemical searches.")
        else:
             feedback_parts.append("✅ VLM confirmed navigation workflow.")
             
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if text report is very good, give benefit of doubt for VLM portion
        if score >= 60: 
            score += 20
            feedback_parts.append("⚠️ VLM check failed, awarding points based on strong report content.")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }