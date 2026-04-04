#!/usr/bin/env python3
"""
Verifier for ecfr_water_quality_research task.

Task: Research EPA National Primary Drinking Water Regulations (40 CFR Part 141) on eCFR.gov.
Identify MCLs for Arsenic, Nitrate, and TTHM. Save to JSON and bookmark pages.

Scoring (100 points total, pass threshold 70):
1. eCFR Navigation (10 pts): Visited ecfr.gov Title 40/Part 141.
2. Bookmark Creation (15 pts): "EPA Compliance" folder exists with ecfr.gov link.
3. JSON Creation (15 pts): Valid JSON file exists and is fresh.
4. Arsenic Data (20 pts): Correct MCL (0.010 mg/L) and Citation (141.62).
5. Nitrate Data (20 pts): Correct MCL (10 mg/L) and Citation (141.62).
6. TTHM Data (20 pts): Correct MCL (0.080 mg/L) and Citation (141.64).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_ecfr_water_quality_research(traj, env_info, task_info):
    """Verify EPA water quality research task."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    # 1. Read metadata result
    result_json_path = "/tmp/task_result.json"
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_meta_path = tmp.name
    
    try:
        copy_from_env(result_json_path, tmp_meta_path)
        with open(tmp_meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result metadata: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read result metadata"}
    finally:
        if os.path.exists(tmp_meta_path):
            os.unlink(tmp_meta_path)
            
    # 2. Read content file if it exists
    file_content = None
    if meta.get("file_exists") and meta.get("file_fresh"):
        content_path = "/tmp/water_mcl_limits_content.json"
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_content_path = tmp.name
        
        try:
            copy_from_env(content_path, tmp_content_path)
            with open(tmp_content_path, "r", encoding="utf-8") as f:
                file_content = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to read content file: {e}")
        finally:
            if os.path.exists(tmp_content_path):
                os.unlink(tmp_content_path)

    score = 0
    feedback_parts = []
    
    # --- Check 1: Navigation (10 pts) ---
    ecfr_visits = meta.get("ecfr_visits", 0)
    part141_visits = meta.get("part141_visits", 0)
    
    if ecfr_visits > 0 and part141_visits > 0:
        score += 10
        feedback_parts.append("Navigation verified (visited eCFR Part 141) (+10)")
    elif ecfr_visits > 0:
        score += 5
        feedback_parts.append("Visited eCFR but possibly not Part 141 specific pages (+5)")
    else:
        feedback_parts.append("No history of visiting ecfr.gov (+0)")
        
    # --- Check 2: Bookmarks (15 pts) ---
    folder_exists = meta.get("bookmark_folder_exists", 0)
    ecfr_bookmarks = meta.get("ecfr_bookmarks", 0)
    
    if folder_exists and ecfr_bookmarks > 0:
        score += 15
        feedback_parts.append("'EPA Compliance' bookmark folder created with eCFR links (+15)")
    elif folder_exists:
        score += 5
        feedback_parts.append("'EPA Compliance' folder created but empty/wrong links (+5)")
    else:
        feedback_parts.append("Bookmark folder 'EPA Compliance' not found (+0)")
        
    # --- Check 3: JSON File Structure (15 pts) ---
    if file_content:
        score += 15
        feedback_parts.append("Output JSON file exists and is valid (+15)")
    elif meta.get("file_exists"):
        score += 5
        feedback_parts.append("Output file exists but is invalid JSON (+5)")
    else:
        feedback_parts.append("Output file not found (+0)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # --- Check 4, 5, 6: Data Accuracy (60 pts total) ---
    # Expected: 
    # Arsenic: 0.010, 141.62
    # Nitrate: 10, 141.62
    # TTHM: 0.080, 141.64
    
    contaminants = file_content.get("contaminants", {})
    
    # Helper to check entry
    def check_entry(name, expected_val, expected_cit, points):
        entry = contaminants.get(name)
        if not entry:
            return 0, f"{name} missing"
            
        try:
            val = float(entry.get("mcl_mg_L", -1))
        except:
            val = -1
        cit = str(entry.get("citation", ""))
        
        p = 0
        msgs = []
        
        # Value check (exact matches for regulations)
        if val == expected_val:
            p += points / 2
            msgs.append(f"{name} value correct")
        else:
            msgs.append(f"{name} value incorrect (got {val}, expected {expected_val})")
            
        # Citation check
        if expected_cit in cit:
            p += points / 2
            msgs.append(f"{name} citation correct")
        else:
            msgs.append(f"{name} citation incorrect (got '{cit}', expected '{expected_cit}')")
            
        return p, ", ".join(msgs)

    # Arsenic (20 pts)
    p_arsenic, msg_arsenic = check_entry("arsenic", 0.01, "141.62", 20)
    score += p_arsenic
    feedback_parts.append(f"Arsenic: {msg_arsenic} (+{p_arsenic})")

    # Nitrate (20 pts)
    p_nitrate, msg_nitrate = check_entry("nitrate", 10.0, "141.62", 20)
    score += p_nitrate
    feedback_parts.append(f"Nitrate: {msg_nitrate} (+{p_nitrate})")

    # TTHM (20 pts)
    # TTHM is 0.080
    p_tthm, msg_tthm = check_entry("total_trihalomethanes", 0.08, "141.64", 20)
    score += p_tthm
    feedback_parts.append(f"TTHM: {msg_tthm} (+{p_tthm})")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }