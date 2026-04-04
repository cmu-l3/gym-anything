#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ivr_call_flow_design(traj, env_info, task_info):
    """
    Verifies the IVR call flow design task.
    
    Criteria:
    1. File Existence & Modification (10 pts)
    2. PDF Export (10 pts)
    3. Diagram Complexity (Shapes > 15, Edges > 15) (20 pts)
    4. Business Logic: Time of Day Check (15 pts)
    5. Business Logic: Account Validation & Retry (15 pts)
    6. Business Logic: Fraud & Menu structure (15 pts)
    7. Visual Verification (VLM) - Structure check (15 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    analysis = result.get("analysis", {})
    text_content = analysis.get("text_content", "").lower()
    keywords_found = analysis.get("keywords_found", [])
    
    score = 0
    feedback = []
    
    # --- SCORING CRITERIA ---
    
    # 1. File Existence (10 pts)
    if analysis.get("file_exists") and analysis.get("valid_xml"):
        score += 10
        feedback.append("Draw.io file created and valid.")
    else:
        feedback.append("Draw.io file missing or invalid.")
        
    # 2. PDF Export (10 pts)
    if result.get("pdf_export_exists"):
        score += 10
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")
        
    # 3. Diagram Complexity (20 pts)
    shapes = analysis.get("shape_count", 0)
    edges = analysis.get("edge_count", 0)
    if shapes >= 15 and edges >= 15:
        score += 20
        feedback.append(f"Good diagram complexity ({shapes} shapes, {edges} edges).")
    elif shapes >= 8:
        score += 10
        feedback.append(f"Low diagram complexity ({shapes} shapes).")
    else:
        feedback.append("Diagram is empty or too simple.")
        
    # 4. Business Logic: Time of Day (15 pts)
    # Check for keywords related to hours/closed
    time_keywords = ["hours", "closed", "9:00", "5:00", "17:00", "time"]
    if any(k in text_content for k in time_keywords):
        score += 15
        feedback.append("Time-of-day logic detected.")
    else:
        feedback.append("Missing Time-of-day/Business Hours logic.")
        
    # 5. Business Logic: Account Validation (15 pts)
    # Looking for "valid", "retry", "digits"
    val_keywords = ["valid", "retry", "attempt", "account", "digit"]
    hits = sum(1 for k in val_keywords if k in text_content)
    if hits >= 2:
        score += 15
        feedback.append("Account validation/retry logic detected.")
    else:
        feedback.append("Missing Account Validation logic.")
        
    # 6. Business Logic: Fraud & Menu (15 pts)
    # Looking for specific menu items
    menu_keywords = ["fraud", "balance", "mortgage", "loan"]
    hits = sum(1 for k in menu_keywords if k in text_content)
    if hits >= 3:
        score += 15
        feedback.append("Main menu structure detected (Fraud, Balance, Loans).")
    else:
        feedback.append("Incomplete Main Menu structure.")
        
    # 7. Visual Verification (15 pts)
    # We use VLM to ensure it actually looks like a flowchart (connected boxes)
    # and not just a text dump.
    vlm_score = 0
    
    # We need to import VLM utils if available in this environment
    # Assuming standard gym_anything signature
    from gym_anything.vlm import query_vlm, get_final_screenshot
    
    final_img = get_final_screenshot(traj)
    
    if final_img:
        prompt = """
        Analyze this screenshot of a draw.io diagram.
        1. Does it look like a flowchart with connected shapes?
        2. Do you see decision diamonds (rhombus shapes)?
        3. Is there a branching structure?
        
        Answer 'YES' if it looks like a legitimate flowchart diagram, 'NO' otherwise.
        """
        try:
            vlm_resp = query_vlm(prompt=prompt, images=[final_img])
            if vlm_resp and vlm_resp.get("success") and "YES" in vlm_resp.get("parsed", "").upper():
                vlm_score = 15
                feedback.append("VLM confirms flowchart structure.")
            else:
                feedback.append("VLM did not recognize a valid flowchart structure.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: give points if complexity is high enough
            if shapes > 20:
                vlm_score = 15
                feedback.append("VLM skipped, complexity heuristic passed.")
    
    score += vlm_score

    # --- FINAL VERDICT ---
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }