#!/usr/bin/env python3
"""
Verifier for pubchem_chemical_hazard_research task.

Verifies:
1. Browser History: Visits to PubChem compound pages (15 pts)
2. Bookmark Structure: 'Chemical Safety Research' folder with 3+ PubChem links (20 pts)
3. Output File: JSON structure, correctness of chemical data (65 pts)

Total: 100 points
Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pubchem_research(traj, env_info, task_info):
    """
    Verify completion of chemical hazard research task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    # 1. Load System State Result (from export_result.sh)
    system_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                system_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load system result: {e}")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 2. Load User Output File
    user_data = {}
    user_file_valid = False
    
    if system_result.get("output_file_exists", False):
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            try:
                # Path defined in task.json metadata
                output_path = task_info.get("metadata", {}).get("output_file", "/home/ga/Documents/chemical_hazard_summary.json")
                copy_from_env(output_path, tmp.name)
                with open(tmp.name, 'r') as f:
                    user_data = json.load(f)
                user_file_valid = True
            except Exception as e:
                logger.error(f"Failed to load/parse user file: {e}")
            finally:
                if os.path.exists(tmp.name):
                    os.unlink(tmp.name)

    # === SCORING LOGIC ===
    score = 0
    feedback = []

    # Criterion 1: Browser History (15 pts)
    visits = system_result.get("pubchem_history_visits", 0)
    if visits >= 3:
        score += 15
        feedback.append(f"Browser History: Visited {visits} PubChem compound pages (+15)")
    elif visits > 0:
        score += 5
        feedback.append(f"Browser History: Partial visits ({visits}) (+5)")
    else:
        feedback.append("Browser History: No PubChem compound pages visited (0)")

    # Criterion 2: Bookmarks (20 pts)
    folder_found = system_result.get("bookmark_folder_found", False)
    pubchem_bms = system_result.get("pubchem_bookmarks_in_folder", 0)

    if folder_found:
        if pubchem_bms >= 3:
            score += 20
            feedback.append(f"Bookmarks: Folder found with {pubchem_bms} PubChem bookmarks (+20)")
        elif pubchem_bms > 0:
            score += 10
            feedback.append(f"Bookmarks: Folder found but only {pubchem_bms} PubChem bookmarks (+10)")
        else:
            score += 5
            feedback.append("Bookmarks: Folder found but empty (+5)")
    else:
        feedback.append("Bookmarks: 'Chemical Safety Research' folder not found (0)")

    # Criterion 3: JSON File Structure & Content (65 pts)
    if not user_file_valid:
        feedback.append("Output File: Invalid or missing JSON file (0)")
    elif not system_result.get("output_file_created_during_task", False):
        feedback.append("Output File: File timestamp indicates it was not created during this task (0)")
    else:
        # File exists and is valid JSON
        score += 5 
        
        required_chems = ["acetone", "sodium_hydroxide", "toluene"]
        expected_data = task_info.get("metadata", {}).get("expected_data", {})
        
        # Normalize keys
        data_norm = {k.lower().replace(" ", "_"): v for k, v in user_data.items()}

        for chem in required_chems:
            if chem in data_norm:
                chem_entry = data_norm[chem]
                chem_score = 0
                chem_feedback_parts = []
                
                # Check 1: Signal Word (5 pts per chem)
                signal = chem_entry.get("ghs_signal_word", "").lower()
                expected_signal = expected_data[chem]["signal_word"][0].lower()
                if expected_signal in signal:
                    chem_score += 5
                else:
                    chem_feedback_parts.append(f"Wrong signal word '{signal}'")

                # Check 2: H-Codes (10 pts per chem)
                # We check if required H-codes are present in the list
                h_codes = chem_entry.get("ghs_hazard_statements", [])
                # Normalize H-codes (extract H\d{3})
                import re
                found_codes = set()
                if isinstance(h_codes, list):
                    for h in h_codes:
                        match = re.search(r"H\d{3}", str(h))
                        if match:
                            found_codes.add(match.group(0))
                
                req_codes = set(expected_data[chem]["h_codes_required"])
                if req_codes.issubset(found_codes):
                    chem_score += 10
                elif len(found_codes) > 0:
                    chem_score += 5 # Partial credit for finding some codes
                    chem_feedback_parts.append(f"Missing specific H-codes (Found: {found_codes})")
                else:
                    chem_feedback_parts.append("No valid H-codes found")

                # Check 3: NFPA (5 pts per chem)
                nfpa = chem_entry.get("nfpa_fire", None)
                # Only strictly checking Fire for Acetone/Toluene and Health for NaOH for simplicity
                if chem == "acetone" or chem == "toluene":
                    if str(nfpa) == "3":
                        chem_score += 5
                    else:
                        chem_feedback_parts.append(f"NFPA Fire mismatch (got {nfpa})")
                elif chem == "sodium_hydroxide":
                    health = chem_entry.get("nfpa_health", None)
                    if str(health) == "3":
                        chem_score += 5
                    else:
                        chem_feedback_parts.append(f"NFPA Health mismatch (got {health})")
                
                score += chem_score
                if chem_feedback_parts:
                    feedback.append(f"Data {chem}: {', '.join(chem_feedback_parts)}")
                else:
                    feedback.append(f"Data {chem}: Perfect (+20)")
            else:
                feedback.append(f"Data {chem}: Key missing in JSON")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback)
    }