#!/usr/bin/env python3
"""
Verifier for generate_flood_warning_json task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_flood_warning_json(traj, env_info, task_info):
    """
    Verify the flood warning JSON feed.
    
    Criteria:
    1. Valid JSON file created (10 pts)
    2. Schema matches requirements (15 pts)
    3. Accuracy of extracted data vs Ground Truth (WSE, Flow) (30 pts)
    4. Correct calculation of Depth and Risk Levels (25 pts)
    5. Anti-gaming checks (File created during task) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    agent_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    truth_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    meta_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    score = 0
    feedback = []
    
    try:
        # Copy files
        try:
            copy_from_env("/tmp/task_result.json", meta_file.name)
            with open(meta_file.name, 'r') as f:
                meta = json.load(f)
        except:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task metadata"}

        # Check existence
        if not meta.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Output file dashboard_feed.json not found."}
        
        if not meta.get("file_created_during_task", False):
            feedback.append("Warning: Output file timestamp indicates it wasn't modified during task.")
            # We penalize but continue to check content (maybe they overwrote it quickly?)
        else:
            score += 20
            feedback.append("File created during task.")

        # Load Agent Output
        try:
            copy_from_env("/tmp/agent_output.json", agent_file.name)
            with open(agent_file.name, 'r') as f:
                agent_data = json.load(f)
            score += 10 # Valid JSON
            feedback.append("Valid JSON format.")
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Invalid JSON file: {e}"}

        # Load Ground Truth
        truth_data = {}
        try:
            copy_from_env("/tmp/ground_truth_data.json", truth_file.name)
            with open(truth_file.name, 'r') as f:
                truth_data = json.load(f)
        except:
            feedback.append("Warning: Ground truth generation failed. Verifying logic consistency only.")

        # --- Schema Verification (15 pts) ---
        has_schema = True
        if "cross_sections" not in agent_data or not isinstance(agent_data["cross_sections"], list):
            has_schema = False
        elif len(agent_data["cross_sections"]) > 0:
            sample = agent_data["cross_sections"][0]
            if not all(k in sample for k in ["river_station", "stats", "status"]):
                has_schema = False
            if "risk_level" not in sample.get("status", {}):
                has_schema = False
        
        if has_schema:
            score += 15
            feedback.append("Schema structure correct.")
        else:
            feedback.append("Incorrect JSON schema structure.")

        # --- Data Accuracy Verification (30 pts) ---
        # Compare a sample of stations
        truth_xs = truth_data.get("cross_sections", {})
        
        matches = 0
        checked = 0
        wse_errors = []
        
        if truth_xs:
            for item in agent_data.get("cross_sections", []):
                rs = item.get("river_station")
                if rs in truth_xs:
                    checked += 1
                    gt = truth_xs[rs]
                    val = item.get("stats", {})
                    
                    # Check WSE (Tolerance 0.1 ft)
                    if abs(val.get("max_wse_ft", -999) - gt["max_wse"]) < 0.1:
                        matches += 1
                    else:
                        wse_errors.append(f"{rs}: Agent {val.get('max_wse_ft')} vs GT {gt['max_wse']}")
            
            if checked > 0:
                accuracy = matches / checked
                if accuracy > 0.9:
                    score += 30
                    feedback.append("Data extraction highly accurate.")
                elif accuracy > 0.5:
                    score += 15
                    feedback.append("Data extraction partially accurate.")
                else:
                    feedback.append(f"Data extraction inaccurate. Errors: {wse_errors[:3]}...")
            else:
                feedback.append("No matching river stations found between output and ground truth.")
        else:
            # Fallback if GT failed: check for plausible values
            # WSE should be > 0, Flow > 0
            plausible = 0
            for item in agent_data.get("cross_sections", []):
                stats = item.get("stats", {})
                if stats.get("max_wse_ft", 0) > 600 and stats.get("max_flow_cfs", 0) > 0:
                    plausible += 1
            if plausible > 0:
                score += 15 # Partial credit
                feedback.append("Data looks plausible (Ground truth missing).")

        # --- Logic & Consistency Verification (25 pts) ---
        # Check: Depth = WSE - Flow? No, WSE - Invert. We don't have Invert in GT easily.
        # But we can check internal consistency: Depth > 0 and Risk Level matches Depth.
        
        logic_errors = 0
        logic_checks = 0
        
        for item in agent_data.get("cross_sections", []):
            stats = item.get("stats", {})
            status = item.get("status", {})
            
            depth = stats.get("max_depth_ft", -1)
            risk = status.get("risk_level", "UNKNOWN")
            
            logic_checks += 1
            
            # Verify Thresholds
            expected_risk = "NORMAL"
            if depth >= 15.0:
                expected_risk = "CRITICAL"
            elif depth >= 10.0:
                expected_risk = "WARNING"
            
            if risk != expected_risk:
                logic_errors += 1
        
        if logic_checks > 0:
            if logic_errors == 0:
                score += 25
                feedback.append("Risk logic perfectly applied.")
            elif logic_errors / logic_checks < 0.1:
                score += 15
                feedback.append("Risk logic mostly correct.")
            else:
                feedback.append(f"Risk logic failed in {logic_errors}/{logic_checks} cases.")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification script error: {e}"}
        
    finally:
        # Cleanup
        for f in [agent_file, truth_file, meta_file]:
            if os.path.exists(f.name):
                os.unlink(f.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }