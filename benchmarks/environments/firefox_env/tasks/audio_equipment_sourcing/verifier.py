#!/usr/bin/env python3
"""
Verifier for audio_equipment_sourcing@1

Checks:
1. Browser History (visits to 3 manufacturer sites).
2. Bookmarks (Folder 'Studio Tech Specs' with 3+ bookmarks).
3. Downloads (3+ new PDF files > 50KB).
4. JSON Output (Data accuracy for Impedance and Sensitivity).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_audio_equipment_sourcing(traj, env_info, task_info):
    # 1. Setup interface
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    # 2. Retrieve Exported Result JSON (Metadata about browser/files)
    meta_path = "/tmp/audio_eq_meta.json"
    try:
        copy_from_env("/tmp/task_result.json", meta_path)
        with open(meta_path, 'r') as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task metadata: {e}"}
    finally:
        if os.path.exists(meta_path): os.remove(meta_path)

    # 3. Retrieve User's Output JSON (The mic specs)
    user_json_path = "/tmp/mic_specs_user.json"
    user_data = {}
    try:
        copy_from_env("/home/ga/Documents/mic_specs.json", user_json_path)
        with open(user_json_path, 'r') as f:
            user_data = json.load(f)
    except Exception:
        # File might not exist, handled in scoring
        pass
    finally:
        if os.path.exists(user_json_path): os.remove(user_json_path)

    # 4. Scoring Logic
    score = 0
    feedback = []
    
    # --- Criterion 1: Manufacturer Sites Visited (15 pts) ---
    hist = meta.get("history", {})
    sites_visited = 0
    if hist.get("shure", 0) > 0: sites_visited += 1
    if hist.get("neumann", 0) > 0: sites_visited += 1
    if hist.get("audio_technica", 0) > 0: sites_visited += 1
    
    hist_score = sites_visited * 5
    score += hist_score
    feedback.append(f"Manufacturer sites visited: {sites_visited}/3 ({hist_score}/15 pts)")

    # --- Criterion 2: Bookmarks Organized (15 pts) ---
    bm = meta.get("bookmarks", {})
    if bm.get("folder_exists", 0):
        count = bm.get("count", 0)
        if count >= 3:
            score += 15
            feedback.append("Bookmark folder 'Studio Tech Specs' created with 3+ items (15/15 pts)")
        elif count > 0:
            score += 10
            feedback.append(f"Bookmark folder created but only has {count} items (10/15 pts)")
        else:
            score += 5
            feedback.append("Bookmark folder created but is empty (5/15 pts)")
    else:
        feedback.append("Bookmark folder 'Studio Tech Specs' not found (0/15 pts)")

    # --- Criterion 3: PDFs Downloaded (20 pts) ---
    pdf_count = meta.get("downloads", {}).get("pdf_count", 0)
    if pdf_count >= 3:
        score += 20
        feedback.append(f"3+ valid PDFs downloaded ({pdf_count} found) (20/20 pts)")
    elif pdf_count > 0:
        partial = pdf_count * 5
        score += partial
        feedback.append(f"Only {pdf_count} PDF(s) downloaded ({partial}/20 pts)")
    else:
        feedback.append("No valid PDF downloads found (0/20 pts)")

    # --- Criterion 4: JSON File Created (10 pts) ---
    output_meta = meta.get("output_file", {})
    if output_meta.get("exists", 0) and output_meta.get("fresh", 0):
        score += 10
        feedback.append("Output JSON file created and is fresh (10/10 pts)")
    elif output_meta.get("exists", 0):
        score += 5
        feedback.append("Output JSON exists but modification time is old (5/10 pts)")
    else:
        feedback.append("Output JSON file not found (0/10 pts)")

    # --- Criterion 5: Data Accuracy (40 pts) ---
    # Expected values
    specs = {
        "shure_sm7b": {"imp": 150, "sens": [-59, 1.12]}, # 150 ohm, -59 dBV or 1.12 mV
        "neumann_u87ai": {"imp": 200, "sens": [-31, 28, 20]}, # 200 ohm, ~28mV or ~20mV (depends on mode/source), approx -31dBV
        "at2020": {"imp": 100, "sens": [-37, 14.1]} # 100 ohm, -37 dBV or 14.1 mV
    }
    
    # Helper for checking values with tolerance
    def check_val(val, targets, tolerance=0.15):
        try:
            v = float(val)
            for t in targets:
                if abs(v - t) <= abs(t * tolerance) or abs(v - t) < 0.5:
                    return True
            return False
        except:
            return False

    data_score = 0
    max_data_score = 40
    per_mic_score = 13 # roughly
    
    if user_data:
        for key, ground_truth in specs.items():
            mic_entry = user_data.get(key, {})
            if not mic_entry:
                feedback.append(f"Missing data for {key}")
                continue
                
            # Check Impedance
            imp_ok = check_val(mic_entry.get("impedance_ohms", 0), [ground_truth["imp"]])
            
            # Check Sensitivity (check both keys provided in description examples)
            sens_val = mic_entry.get("sensitivity_dbv_pa") or mic_entry.get("sensitivity_mv_pa") or 0
            sens_ok = check_val(sens_val, ground_truth["sens"])
            
            if imp_ok and sens_ok:
                data_score += 13
            elif imp_ok or sens_ok:
                data_score += 6
                feedback.append(f"{key}: Partial match (Impedance: {imp_ok}, Sensitivity: {sens_ok})")
            else:
                feedback.append(f"{key}: Incorrect values. Got Imp={mic_entry.get('impedance_ohms')}, Sens={sens_val}")

    # Cap data score at 40
    data_score = min(data_score, 40)
    score += data_score
    feedback.append(f"Data accuracy score: {data_score}/40 pts")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "\n".join(feedback)
    }