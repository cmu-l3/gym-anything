#!/usr/bin/env python3
"""
Verifier for hpv16_circular_linearization task.

Scoring breakdown (100 points total):
  GenBank file created and valid:          10
  DB Annotation count > 15 (used DB):      15
  BamHI annotated exactly once:            15
  SphI annotated exactly once:             15
  EcoRI excluded (0 annotations):          15
  HindIII excluded (0 annotations):        10
  Report mentions enzymes and exclusions:  20
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hpv16_circular_linearization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    score = 0
    feedback_parts = []
    subscores = {}

    # 1. Fetch metadata JSON
    result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_json = f.name
    try:
        copy_from_env("/tmp/hpv_task_result.json", tmp_json)
        with open(tmp_json, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
    finally:
        if os.path.exists(tmp_json):
            os.remove(tmp_json)

    # 2. Extract GenBank file
    gb_content = ""
    if result.get("gb_exists"):
        with tempfile.NamedTemporaryFile(suffix=".gb", delete=False) as f:
            tmp_gb = f.name
        try:
            copy_from_env("/home/ga/UGENE_Data/hpv/results/hpv16_single_cutters.gb", tmp_gb)
            with open(tmp_gb, 'r') as f:
                gb_content = f.read()
        except Exception as e:
            logger.error(f"Failed to read GB file: {e}")
        finally:
            if os.path.exists(tmp_gb):
                os.remove(tmp_gb)

    # 3. Extract Report file
    report_content = ""
    if result.get("report_exists"):
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
            tmp_txt = f.name
        try:
            copy_from_env("/home/ga/UGENE_Data/hpv/results/linearization_report.txt", tmp_txt)
            with open(tmp_txt, 'r') as f:
                report_content = f.read()
        except Exception as e:
            logger.error(f"Failed to read Report file: {e}")
        finally:
            if os.path.exists(tmp_txt):
                os.remove(tmp_txt)

    # Check anti-gaming
    if not result.get("gb_created_during_task", False) and result.get("gb_exists"):
        feedback_parts.append("WARNING: GenBank file was not created during the task.")
    
    # ---------------------------------------------------------
    # Criterion 1: GenBank file created and valid (10 pts)
    # ---------------------------------------------------------
    c1 = 0
    if result.get("gb_exists") and "LOCUS" in gb_content and "FEATURES" in gb_content:
        c1 = 10
        feedback_parts.append("GenBank file created and valid (+10)")
    else:
        feedback_parts.append("GenBank file MISSING or invalid (0)")
    
    score += c1
    subscores["gb_valid"] = c1

    # Extract FEATURES block for deep analysis
    features_block = ""
    if "FEATURES" in gb_content:
        if "ORIGIN" in gb_content:
            features_block = gb_content.split("ORIGIN")[0].split("FEATURES")[1]
        else:
            features_block = gb_content.split("FEATURES")[1]

    features_lower = features_block.lower()

    # ---------------------------------------------------------
    # Criterion 2: DB Annotation count > 15 (15 pts)
    # ---------------------------------------------------------
    c2 = 0
    # Count occurrences of standard UGENE qualifier markers for enzyme labels
    # e.g., /label="BamHI" or /note="BamHI"
    label_count = len(re.findall(r'/(label|note)=', features_lower))
    
    if label_count > 15:
        c2 = 15
        feedback_parts.append(f"DB annotations present ({label_count} found) (+15)")
    elif label_count > 5:
        c2 = 7
        feedback_parts.append(f"Some annotations present ({label_count} found) (+7)")
    else:
        feedback_parts.append(f"Too few annotations ({label_count}). Standard DB search not performed (0)")
    
    score += c2
    subscores["db_annotations"] = c2

    # ---------------------------------------------------------
    # Criterion 3: BamHI exactly 1 (15 pts)
    # ---------------------------------------------------------
    c3 = 0
    bamhi_hits = len(re.findall(r'bamhi', features_lower))
    if bamhi_hits == 1:
        c3 = 15
        feedback_parts.append("BamHI annotated exactly once (+15)")
    elif bamhi_hits > 1:
        feedback_parts.append(f"BamHI annotated {bamhi_hits} times (expected 1) (0)")
    else:
        feedback_parts.append("BamHI NOT annotated (0)")
    
    score += c3
    subscores["bamhi_annotated"] = c3

    # ---------------------------------------------------------
    # Criterion 4: SphI exactly 1 (15 pts)
    # ---------------------------------------------------------
    c4 = 0
    sphi_hits = len(re.findall(r'sphi', features_lower))
    if sphi_hits == 1:
        c4 = 15
        feedback_parts.append("SphI annotated exactly once (+15)")
    elif sphi_hits > 1:
        feedback_parts.append(f"SphI annotated {sphi_hits} times (expected 1) (0)")
    else:
        feedback_parts.append("SphI NOT annotated (0)")
    
    score += c4
    subscores["sphi_annotated"] = c4

    # ---------------------------------------------------------
    # Criterion 5: EcoRI excluded (15 pts)
    # ---------------------------------------------------------
    c5 = 0
    ecori_hits = len(re.findall(r'ecori', features_lower))
    if c1 > 0 and ecori_hits == 0:
        c5 = 15
        feedback_parts.append("EcoRI correctly excluded (+15)")
    elif ecori_hits > 0:
        feedback_parts.append(f"EcoRI incorrectly included {ecori_hits} times (0)")
    else:
        feedback_parts.append("EcoRI excluded, but file invalid (0)")
    
    score += c5
    subscores["ecori_excluded"] = c5

    # ---------------------------------------------------------
    # Criterion 6: HindIII excluded (10 pts)
    # ---------------------------------------------------------
    c6 = 0
    hindiii_hits = len(re.findall(r'hindiii', features_lower))
    if c1 > 0 and hindiii_hits == 0:
        c6 = 10
        feedback_parts.append("HindIII correctly excluded (+10)")
    elif hindiii_hits > 0:
        feedback_parts.append(f"HindIII incorrectly included {hindiii_hits} times (0)")
    else:
        feedback_parts.append("HindIII excluded, but file invalid (0)")
    
    score += c6
    subscores["hindiii_excluded"] = c6

    # ---------------------------------------------------------
    # Criterion 7: Report contents (20 pts)
    # ---------------------------------------------------------
    c7 = 0
    if result.get("report_exists"):
        r_lower = report_content.lower()
        if 'bamhi' in r_lower and 'sphi' in r_lower:
            c7 += 10
            feedback_parts.append("Report mentions BamHI and SphI (+10)")
        else:
            feedback_parts.append("Report missing BamHI/SphI mentions")
            
        if 'ecori' in r_lower and 'hindiii' in r_lower:
            c7 += 10
            feedback_parts.append("Report discusses EcoRI and HindIII exclusions (+10)")
        else:
            feedback_parts.append("Report missing EcoRI/HindIII discussion")
    else:
        feedback_parts.append("Report file MISSING (0)")
    
    score += c7
    subscores["report_content"] = c7

    # VLM Check integration (optional validation over trajectory)
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    vlm_feedback = ""
    try:
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = """Look at these screenshots from a bioinformatics tool.
            Did the user open the 'Find restriction sites' dialog and configure parameters?
            Look for check boxes or numerical fields for Min hits / Max hits and Circular options.
            Respond in JSON format: {"used_restriction_tool": true/false}"""
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("parsed", {}).get("used_restriction_tool"):
                vlm_feedback = "VLM confirmed restriction tool usage."
            else:
                vlm_feedback = "VLM could not confirm restriction tool usage."
    except Exception as e:
        vlm_feedback = f"VLM check skipped/failed: {e}"

    # To pass, they must have achieved at least some structural constraints + score threshold
    # The exclusions (c5, c6) prove the hit-filtering logic worked.
    key_criteria_met = (c5 == 15 and c6 == 10 and c1 == 10)
    passed = score >= 70 and key_criteria_met

    full_feedback = " | ".join(feedback_parts)
    if vlm_feedback:
        full_feedback += f" || {vlm_feedback}"

    return {
        "passed": passed,
        "score": score,
        "feedback": full_feedback,
        "subscores": subscores
    }