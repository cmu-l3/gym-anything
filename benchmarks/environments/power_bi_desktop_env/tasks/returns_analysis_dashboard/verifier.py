#!/usr/bin/env python3
"""
Verifier for returns_analysis_dashboard task.

Scoring (100 points total):
- File Saved (10 pts)
- Data Modeling (40 pts): Tables present, Relationship inferred, Measures created
- Visualization (30 pts): Matrix and Scatter Chart present
- VLM Verification (20 pts): Visual check of the report page

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logger = logging.getLogger(__name__)

def verify_returns_analysis_dashboard(traj, env_info, task_info):
    """Verify Returns Analysis Dashboard task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve programmatic result from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    # Path inside the Windows VM
    vm_result_path = "C:/Users/Docker/Desktop/returns_analysis_result.json"
    
    try:
        copy_from_env(vm_result_path, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        # Even if file load fails, we try VLM as fallback if screenshot exists
        result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Programmatic Checks (80 pts) ---
    
    # 1. File Existence & Anti-Gaming (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("✅ File saved and modified during task")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("⚠️ File exists but timestamp check failed")
    else:
        feedback_parts.append("❌ Returns_Dashboard.pbix not found")

    # 2. Measures (30 pts)
    measures = result.get('measures_found', [])
    if "Total_Orders" in measures:
        score += 15
        feedback_parts.append("✅ Measure 'Total_Orders' found")
    else:
        feedback_parts.append("❌ Measure 'Total_Orders' missing")
        
    if "Return_Rate" in measures:
        score += 15
        feedback_parts.append("✅ Measure 'Return_Rate' found")
    else:
        feedback_parts.append("❌ Measure 'Return_Rate' missing")

    # 3. Data Model & Relationship (10 pts)
    tables = result.get('tables_found', [])
    rel_hint = result.get('relationship_hint', False)
    if "Orders" in tables and "Returns" in tables:
        score += 5
        feedback_parts.append("✅ Both tables imported")
    
    if rel_hint:
        score += 5
        feedback_parts.append("✅ Relationship inferred from usage")

    # 4. Visuals (30 pts)
    visuals = result.get('visuals_found', [])
    if "matrix" in visuals:
        score += 15
        feedback_parts.append("✅ Matrix visual found")
    else:
        feedback_parts.append("❌ Matrix visual missing")
        
    if "scatterChart" in visuals:
        score += 15
        feedback_parts.append("✅ Scatter chart found")
    else:
        feedback_parts.append("❌ Scatter chart missing")

    # --- VLM Verification (20 pts) ---
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = """
        Review this Power BI report screenshot.
        1. Is there a Scatter Chart visible (bubbles/dots)?
        2. Is there a Matrix or Table visual visible?
        3. Does the report look like it analyzes 'Returns' (e.g., fields like Return_Rate, Region)?
        """
        vlm_res = query_vlm(image=final_screenshot, prompt=prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            # Simple heuristic based on response text or structured parsing if available
            # Assuming query_vlm returns a generic positive sentiment or we check content
            text_response = vlm_res.get('text', '').lower()
            
            vlm_score = 0
            if 'scatter' in text_response:
                vlm_score += 10
            if 'matrix' in text_response or 'table' in text_response:
                vlm_score += 10
            
            # Cap VLM score at 20
            score += min(20, vlm_score)
            feedback_parts.append(f"VLM Analysis: {text_response[:50]}...")
        else:
            feedback_parts.append("⚠️ VLM verification failed")
    else:
        feedback_parts.append("⚠️ No screenshot for VLM verification")

    # Final Pass Check
    # Requirement: File exists + Return_Rate measure + One visual correct
    key_requirements = (
        result.get('file_exists') and 
        "Return_Rate" in measures and 
        len(visuals) > 0
    )
    
    passed = score >= 70 and key_requirements

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }