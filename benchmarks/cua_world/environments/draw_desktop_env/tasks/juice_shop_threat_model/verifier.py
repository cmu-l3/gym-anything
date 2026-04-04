#!/usr/bin/env python3
"""
Verifier for juice_shop_threat_model task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_juice_shop_threat_model(traj, env_info, task_info):
    """
    Verify the STRIDE threat model task.
    
    Criteria:
    1. File creation/modification (10 pts)
    2. DFD Components present (Shapes) (20 pts)
    3. Data flows present (Edges) (15 pts)
    4. Trust boundaries present (Dashed styles) (15 pts)
    5. STRIDE analysis present (Text keywords) (15 pts)
    6. Multi-page diagram (15 pts)
    7. PNG Export (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback = []
    
    analysis = result.get("analysis", {})
    text_content = analysis.get("text_content", "").lower()
    labels = analysis.get("labels", [])
    
    # 1. File Status (10 pts)
    if result.get("file_exists") and result.get("file_modified_after_start"):
        score += 10
        feedback.append("File saved successfully.")
    else:
        feedback.append("File not saved or not modified.")
        return {"passed": False, "score": 0, "feedback": "Task failed: No output file saved."}

    # 2. DFD Components (20 pts)
    # Check for keywords mapping to required components
    required_components = {
        "User/Browser": ["browser", "user", "client"],
        "Stripe": ["stripe", "payment"],
        "SMTP/Email": ["smtp", "email", "mail"],
        "Angular/SPA": ["angular", "spa", "frontend"],
        "Express/API": ["express", "api", "backend", "node"],
        "Auth": ["auth", "jwt", "login"],
        "Database": ["sqlite", "db", "database"],
        "File System": ["file", "upload", "ftp"]
    }
    
    components_found = 0
    missing_components = []
    
    for comp_name, keywords in required_components.items():
        found = False
        for k in keywords:
            if k in text_content:
                found = True
                break
        if found:
            components_found += 1
        else:
            missing_components.append(comp_name)
            
    if components_found >= 6:
        score += 20
        feedback.append(f"DFD Components: Found {components_found}/8.")
    elif components_found >= 4:
        score += 10
        feedback.append(f"DFD Components: Found {components_found}/8 (Partial). Missing: {', '.join(missing_components)}")
    else:
        feedback.append(f"DFD Components: Found only {components_found}. Need at least 4.")

    # 3. Data Flows (15 pts)
    num_edges = analysis.get("num_edges", 0)
    if num_edges >= 8:
        score += 15
        feedback.append(f"Data Flows: {num_edges} edges found.")
    elif num_edges >= 4:
        score += 7
        feedback.append(f"Data Flows: {num_edges} edges found (Partial).")
    else:
        feedback.append(f"Data Flows: Only {num_edges} found.")

    # 4. Trust Boundaries (15 pts)
    # Checked via dashed line styles
    dashed_count = analysis.get("dashed_containers", 0)
    if dashed_count >= 2:
        score += 15
        feedback.append(f"Trust Boundaries: {dashed_count} dashed regions found.")
    elif dashed_count == 1:
        score += 7
        feedback.append("Trust Boundaries: 1 dashed region found (Partial).")
    else:
        feedback.append("Trust Boundaries: No dashed boundary shapes found.")

    # 5. STRIDE Analysis (15 pts)
    found_stride = analysis.get("stride_keywords_found", [])
    if len(found_stride) >= 4:
        score += 15
        feedback.append(f"STRIDE Analysis: Found {len(found_stride)} categories.")
    elif len(found_stride) >= 2:
        score += 7
        feedback.append(f"STRIDE Analysis: Found {len(found_stride)} categories (Partial).")
    else:
        feedback.append("STRIDE Analysis: No significant STRIDE keywords found.")

    # 6. Multi-page (15 pts)
    num_pages = analysis.get("num_pages", 0)
    if num_pages >= 2:
        score += 15
        feedback.append("Structure: Multi-page diagram created.")
    else:
        feedback.append("Structure: Single page only (expected DFD + Analysis pages).")

    # 7. PNG Export (10 pts)
    if result.get("png_exists") and result.get("png_size", 0) > 2000:
        score += 10
        feedback.append("Export: PNG file created.")
    else:
        feedback.append("Export: PNG missing or too small.")

    # VLM Verification fallback (if programmed checks are borderline)
    # (Optional implementation detail - usually rely on Programmatic for this precise task)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }