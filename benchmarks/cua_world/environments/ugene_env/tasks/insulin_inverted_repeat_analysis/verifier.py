#!/usr/bin/env python3
"""
Verifier for insulin_inverted_repeat_analysis task.

Uses `copy_from_env` to read exported files and evaluate success.
Applies Multi-Criteria Scoring:
1. File Existence and Anti-Gaming (created during task)
2. GFF Format and Biological Coordinate Validity
3. Summary Report Match
4. VLM Trajectory Verification (ensuring UI was used instead of fake files)
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insulin_inverted_repeat_analysis(traj, env_info, task_info):
    # Obtain the secure copy method provided by the framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Execution framework error: copy_from_env not available"}

    feedback_parts = []
    score = 0
    subscores = {}

    # 1. Read the exported result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    gff_info = result.get("gff", {})
    txt_info = result.get("summary", {})

    # ===================================================================
    # Criterion 1: File Existence & Anti-Gaming (Timestamps) [30 Points]
    # ===================================================================
    c1 = 0
    if gff_info.get("exists") and txt_info.get("exists"):
        c1 += 15
        if gff_info.get("created_during_task") and txt_info.get("created_during_task"):
            c1 += 15
            feedback_parts.append("Outputs exist and created during task (+30)")
        else:
            feedback_parts.append("Outputs exist but timestamps suggest they were generated prior to task (+15)")
    else:
        feedback_parts.append("Required output files (GFF or Summary) are missing (0)")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "; ".join(feedback_parts),
            "subscores": {"file_presence": 0}
        }
    
    score += c1
    subscores["file_presence"] = c1

    # ===================================================================
    # Criterion 2: GFF Format & Biological Validity [30 Points]
    # ===================================================================
    c2 = 0
    valid_features = 0
    first_start = None
    first_end = None

    temp_gff = tempfile.NamedTemporaryFile(delete=False, suffix='.gff')
    try:
        copy_from_env(gff_info.get("path"), temp_gff.name)
        with open(temp_gff.name, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    parts = line.split('\t')
                    if len(parts) >= 8:
                        try:
                            start = int(parts[3])
                            end = int(parts[4])
                            valid_features += 1
                            if valid_features == 1:
                                first_start = start
                                first_end = end
                        except ValueError:
                            pass
        
        if valid_features > 0:
            c2 += 15
            feedback_parts.append(f"GFF valid with {valid_features} parsed features (+15)")
            # Checking length config (>= 8bp expected per instructions)
            if first_end is not None and first_start is not None:
                if (first_end - first_start + 1) >= 8:
                    c2 += 15
                    feedback_parts.append("Features match minimum length biological criteria (+15)")
                else:
                    feedback_parts.append("Feature length violates configured constraints (+0)")
        else:
            feedback_parts.append("GFF is empty or malformed (0)")

    except Exception as e:
        feedback_parts.append(f"Error parsing GFF: {e} (0)")
    finally:
        if os.path.exists(temp_gff.name):
            os.unlink(temp_gff.name)

    score += c2
    subscores["gff_validity"] = c2

    # ===================================================================
    # Criterion 3: Summary Report Contents [15 Points]
    # ===================================================================
    c3 = 0
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(txt_info.get("path"), temp_txt.name)
        with open(temp_txt.name, 'r') as f:
            summary_content = f.read()
        
        # Check if the number of valid features is reported
        if str(valid_features) in summary_content and valid_features > 0:
            c3 += 10
            feedback_parts.append("Summary accurately reports feature count (+10)")
        elif any(char.isdigit() for char in summary_content):
            c3 += 5
            feedback_parts.append("Summary contains numerical data but count mismatch (+5)")
            
        # Check if coordinates of the first feature are mentioned
        if first_start and first_end and (str(first_start) in summary_content) and (str(first_end) in summary_content):
            c3 += 5
            feedback_parts.append("Summary reports correct feature coordinates (+5)")

    except Exception as e:
        feedback_parts.append(f"Error reading summary: {e} (0)")
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    score += c3
    subscores["summary_report"] = c3

    # ===================================================================
    # Criterion 4: VLM Trajectory Verification [25 Points]
    # Proves the agent actually used the Repeat Finder UI (Anti-Gaming)
    # ===================================================================
    c4 = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        prompt = """You are auditing a bioinformatics agent using the UGENE software.
Did the agent open the 'Find repeats' or 'Find tandem repeats' dialog?
Did the agent configure it for 'Inverted repeats' with a length of 8 and Identity of 100%?
Did the agent export features?

Respond strictly in JSON:
{
    "opened_repeat_finder": true/false,
    "configured_inverted_repeats": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""
        images = frames
        if final_img:
            images.append(final_img)
            
        vlm_resp = query_vlm(images=images, prompt=prompt)
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("opened_repeat_finder"):
                c4 += 15
                feedback_parts.append("VLM confirms Repeat Finder UI was opened (+15)")
            if parsed.get("configured_inverted_repeats"):
                c4 += 10
                feedback_parts.append("VLM confirms configuration for inverted repeats (+10)")
        else:
            feedback_parts.append("VLM check failed or parsed incorrectly (+0)")
            
    except ImportError:
        # Gracefully handle framework missing imports 
        feedback_parts.append("VLM utilities unavailable for trajectory check (+0)")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM verification encountered an error (+0)")
        
    score += c4
    subscores["vlm_trajectory"] = c4

    # ===================================================================
    # Final Decision
    # ===================================================================
    # Pass requires a score of >= 70 AND valid biological features were extracted
    key_criteria_met = valid_features > 0 and c1 == 30
    passed = (score >= 70) and key_criteria_met

    if not key_criteria_met and score >= 70:
        feedback_parts.append("FAILED: Met points threshold but failed critical constraint (Zero features extracted or cheating detected).")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }