#!/usr/bin/env python3
"""
Verifier for insulin_restriction_cloning task.

Multi-Criteria Scoring:
1. Files exist and created during task (20 pts)
2. GB file is structurally valid GenBank (10 pts)
3. GB file contains >= 10 enzyme annotations (20 pts)
4. Report exists and is adequately detailed (10 pts)
5. Report identifies CDS-cutting and non-CDS-cutting enzymes (10 pts)
6. VLM confirms the agent actually used the UGENE UI for restriction analysis (30 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insulin_restriction_cloning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read the export summary JSON
    summary_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/insulin_cloning_result.json", summary_file.name)
        with open(summary_file.name, 'r') as f:
            summary = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export summary: {e}"}
    finally:
        if os.path.exists(summary_file.name):
            os.unlink(summary_file.name)

    task_start = summary.get('task_start', 0)
    gb_exists = summary.get('gb_exists', False)
    gb_mtime = summary.get('gb_mtime', 0)
    report_exists = summary.get('report_exists', False)
    report_mtime = summary.get('report_mtime', 0)

    # Criterion 1: Files created during task (anti-gaming)
    files_created_in_task = False
    if gb_exists and report_exists:
        if gb_mtime >= task_start and report_mtime >= task_start:
            score += 20
            feedback_parts.append("Both output files created during task (+20)")
            files_created_in_task = True
        else:
            feedback_parts.append("Output files exist but timestamps pre-date task start (0)")
    else:
        feedback_parts.append("One or both required output files missing (0)")
        
    # Read GenBank File
    gb_valid = False
    enzyme_count = 0
    if gb_exists:
        gb_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.gb')
        try:
            copy_from_env("/home/ga/UGENE_Data/results/insulin_restriction_annotated.gb", gb_temp.name)
            with open(gb_temp.name, 'r') as f:
                gb_text = f.read()
                
            # Criterion 2: Structural validity
            if "LOCUS" in gb_text and "FEATURES" in gb_text and "ORIGIN" in gb_text:
                score += 10
                gb_valid = True
                feedback_parts.append("Valid GenBank format (+10)")
                
                # Criterion 3: Enzyme annotations presence
                # UGENE saves restriction enzymes as 'misc_feature' or 'restriction_site' with labels
                # Example: misc_feature ... /label="EcoRI"
                feature_blocks = gb_text.split("FEATURES")[1].split("ORIGIN")[0]
                
                # Count generic feature blocks which increase dramatically when enzymes are added
                feature_count = len(re.findall(r'\n\s{5}\w+', feature_blocks))
                
                # Match restriction enzyme naming patterns (e.g., EcoRI, BamHI, HindIII)
                enzyme_matches = set(re.findall(r'\b[A-Z][a-z]{1,3}[A-Z0-9]?[IVX]{1,3}\b', feature_blocks))
                
                if len(enzyme_matches) >= 5 or feature_count > 20:
                    score += 20
                    feedback_parts.append("Abundant enzyme annotations found in sequence (+20)")
                    enzyme_count = max(len(enzyme_matches), feature_count - 10)
                elif len(enzyme_matches) > 0 or feature_count > 5:
                    score += 10
                    feedback_parts.append("Some enzyme annotations found, but fewer than expected (+10)")
                else:
                    feedback_parts.append("No new enzyme annotations found in GenBank file (0)")
            else:
                feedback_parts.append("GenBank file is missing required structural sections (0)")
        except Exception as e:
            feedback_parts.append(f"Failed to parse GenBank file: {e}")
        finally:
            if os.path.exists(gb_temp.name):
                os.unlink(gb_temp.name)

    # Read Report File
    report_detailed = False
    if report_exists:
        rep_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/UGENE_Data/results/cloning_strategy_report.txt", rep_temp.name)
            with open(rep_temp.name, 'r') as f:
                report_text = f.read()
            
            # Criterion 4: Report existence and baseline detail
            if len(report_text) > 100:
                score += 10
                report_detailed = True
                feedback_parts.append("Cloning strategy report is adequately detailed (+10)")
                
                # Criterion 5: Report content (CDS and Enzyme mentions)
                report_lower = report_text.lower()
                has_cds_mention = "cds" in report_lower or "coding" in report_lower or "60" in report_lower
                enzyme_names_in_report = set(re.findall(r'\b[A-Z][a-z]{1,3}[A-Z0-9]?[IVX]{1,3}\b', report_text))
                
                if has_cds_mention and len(enzyme_names_in_report) >= 2:
                    score += 10
                    feedback_parts.append("Report successfully identifies CDS and candidate enzymes (+10)")
                else:
                    feedback_parts.append("Report missing clear CDS analysis or enzyme names (0)")
            else:
                feedback_parts.append("Cloning strategy report is too short to be complete (0)")
        except Exception as e:
            feedback_parts.append(f"Failed to read report file: {e}")
        finally:
            if os.path.exists(rep_temp.name):
                os.unlink(rep_temp.name)

    # Criterion 6: VLM verification of UI usage
    vlm_success = False
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = [img for img in frames + [final] if img is not None]
            
            if images:
                prompt = (
                    "Look closely at these screenshots of a UGENE bioinformatics workflow. "
                    "Did the user open and use the 'Find Restriction Sites' (or 'Find Enzymes') dialog? "
                    "You should look for a dialog box related to restriction enzyme analysis, "
                    "or a side panel/sequence view heavily populated with restriction site annotations. "
                    "Respond with a JSON object: {\"used_enzyme_tool\": true/false, \"reason\": \"...\"}"
                )
                
                vlm_result = query_vlm(images=images, prompt=prompt)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("used_enzyme_tool", False):
                        score += 30
                        vlm_success = True
                        feedback_parts.append("VLM verified restriction enzyme tool usage (+30)")
                    else:
                        feedback_parts.append("VLM did not detect restriction enzyme tool usage (0)")
                else:
                    feedback_parts.append("VLM query failed, skipping visual check.")
        except ImportError:
            feedback_parts.append("VLM utilities unavailable for trajectory check.")

    key_criteria_met = files_created_in_task and gb_valid and report_detailed and enzyme_count > 0
    passed = score >= 70 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }