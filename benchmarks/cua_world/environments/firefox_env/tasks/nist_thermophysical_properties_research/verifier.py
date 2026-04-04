#!/usr/bin/env python3
import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_close(val, target, tolerance_pct):
    if val is None or target is None:
        return False
    try:
        val = float(val)
        target = float(target)
        diff = abs(val - target)
        allowance = (tolerance_pct / 100.0) * target
        return diff <= allowance
    except ValueError:
        return False

def verify_nist_research(traj, env_info, task_info):
    """
    Verifies the NIST Thermophysical Properties Research task.
    
    Criteria:
    1. Browser History: Visited webbook.nist.gov (10 pts)
    2. Bookmarks: Folder "Process Design Data" exists (15 pts)
    3. Bookmarks: >=3 NIST bookmarks in folder (15 pts)
    4. JSON File: Exists & Fresh (10 pts)
    5. Data Accuracy: 50 pts total
       - CAS (exact match): 5 pts per fluid (15 total)
       - MW, Tc, Pc (within tolerance): 3.8 pts per field per fluid (~35 total)
       - Critical Pressure MUST be in bar (checks unit conversion)
    """
    
    # 1. Setup & Read Metadata
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    ref_data = metadata.get('reference_data', {})
    tolerance = metadata.get('tolerance_percent', 2.0)
    
    score = 0
    feedback = []
    
    # 2. Retrieve Export Result (Browser State)
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            feedback.append("Failed to retrieve browser state checks.")
        finally:
            if os.path.exists(tmp.name): os.unlink(tmp.name)
            
    # 3. Retrieve User Output File (JSON Data)
    user_data = {}
    output_exists = task_result.get("output_exists", False)
    
    if output_exists:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            try:
                copy_from_env("/home/ga/Documents/fluid_properties.json", tmp.name)
                with open(tmp.name, 'r') as f:
                    user_data = json.load(f)
            except Exception as e:
                logger.error(f"Failed to load user json: {e}")
                feedback.append("Failed to read fluid_properties.json (invalid format?).")
            finally:
                if os.path.exists(tmp.name): os.unlink(tmp.name)
    
    # --- SCORING ---
    
    # Criterion 1: History (10 pts)
    if task_result.get("nist_visits", 0) > 0:
        score += 10
        feedback.append("Browser history confirmed NIST visit.")
    else:
        feedback.append("No history of visiting webbook.nist.gov found.")

    # Criterion 2: Bookmark Folder (15 pts)
    if task_result.get("bookmark_folder_exists", False):
        score += 15
        feedback.append("Bookmark folder 'Process Design Data' exists.")
    else:
        feedback.append("Bookmark folder 'Process Design Data' missing.")

    # Criterion 3: Bookmarks Count (15 pts)
    # Require at least 3 NIST bookmarks in that folder
    bm_count = task_result.get("bookmark_count", 0)
    if bm_count >= 3:
        score += 15
        feedback.append(f"Found {bm_count} NIST bookmarks in folder.")
    elif bm_count > 0:
        score += 5  # Partial credit
        feedback.append(f"Found {bm_count} bookmarks (expected 3).")
    else:
        feedback.append("No NIST bookmarks found in the target folder.")

    # Criterion 4: File Existence & Freshness (10 pts)
    if output_exists and task_result.get("output_fresh", False):
        score += 10
        feedback.append("Output JSON file created during task.")
    elif output_exists:
        score += 5
        feedback.append("Output JSON exists but timestamp check failed (pre-existing?).")
    else:
        feedback.append("Output JSON file not found.")
        # If file missing, stop checking data
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Criterion 5: Data Accuracy (50 pts total)
    # Structure check
    fluids = ["methanol", "toluene", "r134a"]
    data_points = 0
    max_data_points = len(fluids) * 4 # CAS, MW, Tc, Pc
    
    for fluid in fluids:
        if fluid not in user_data:
            feedback.append(f"Missing key: {fluid}")
            continue
            
        u_props = user_data[fluid]
        ref = ref_data.get(fluid, {})
        
        # Check CAS (String Match)
        if u_props.get("cas_registry_number") == ref.get("cas"):
            score += 5
            feedback.append(f"{fluid} CAS correct.")
        else:
            feedback.append(f"{fluid} CAS mismatch (Expected {ref.get('cas')}).")

        # Check Numerical Fields (MW, Tc, Pc)
        # 35 points distributed across 9 checks (3 fluids * 3 props) ~= 3.88 pts each
        
        # MW
        if is_close(u_props.get("molecular_weight_g_mol"), ref.get("mw"), tolerance):
            score += 4
        else:
            feedback.append(f"{fluid} MW incorrect.")

        # Tc
        if is_close(u_props.get("critical_temperature_k"), ref.get("tc"), tolerance):
            score += 4
        else:
            feedback.append(f"{fluid} Tc incorrect.")

        # Pc (Crucial Unit Conversion Check)
        # We cap score if they likely used MPa instead of bar (off by factor of 10 or 0.1)
        pc_val = u_props.get("critical_pressure_bar")
        if is_close(pc_val, ref.get("pc_bar"), tolerance):
            score += 4
        elif is_close(pc_val, ref.get("pc_bar")/10.0, tolerance):
             feedback.append(f"{fluid} Pc appears to be in MPa (conversion missed).")
        elif is_close(pc_val, ref.get("pc_bar")*1.01325, tolerance): # atm check
             score += 2 # Partial for atm if close
             feedback.append(f"{fluid} Pc appears to be in atm.")
        else:
             feedback.append(f"{fluid} Pc incorrect (Expected ~{ref.get('pc_bar')} bar).")

    # Final tally
    # Max score calculation: 10 + 15 + 15 + 10 + (3 * 5) + (9 * 4) = 50 + 15 + 36 = 101 (capped at 100)
    score = min(score, 100)
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }