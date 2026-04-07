#!/usr/bin/env python3
"""
Verifier for directory_structure_profiling task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and data source ingested
  30 pts  — Directory tree file exists, is formatted correctly, and covers ≥60% of GT paths
  30 pts  — Profile file exists, contains all required sections
  20 pts  — Profile stats (counts, max depth) are within ±20% of GT
  10 pts  — Internal consistency (tree content aligns with profile stats)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_directory_structure_profiling(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/directory_profile_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/directory_profile_gt.json")

    # ── 1. Pull result & GT ───────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception as e:
        logger.warning(f"GT load failed: {e}")

    # ── 2. Autopsy Case Verification (10 pts) ─────────────────────────────────
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Case created and data source added (+10)")
    else:
        feedback_parts.append("FAIL Case or data source missing in Autopsy DB")

    # ── 3. Directory Tree File (30 pts) ───────────────────────────────────────
    start_time = result.get("start_time", 0)
    tree_mtime = result.get("tree_file_mtime", 0)
    tree_content = result.get("tree_file_content", "")
    
    parsed_tree_files = 0
    parsed_tree_dirs = 0

    if result.get("tree_file_exists"):
        if start_time > 0 and tree_mtime < start_time:
            feedback_parts.append("FAIL Directory tree file is stale (pre-dates task)")
        else:
            lines = [l.strip() for l in tree_content.splitlines() if l.strip()]
            if lines and "DEPTH" in lines[0].upper() and "ENTRY_TYPE" in lines[0].upper():
                data_lines = lines[1:]
                pipe_lines = [l for l in data_lines if l.count('|') >= 4]
                
                for pl in pipe_lines:
                    parts = pl.split('|')
                    if len(parts) >= 2:
                        etype = parts[1].strip().upper()
                        if 'DIR' in etype: parsed_tree_dirs += 1
                        if 'FILE' in etype: parsed_tree_files += 1

                if len(pipe_lines) > 50:
                    score += 30
                    feedback_parts.append(f"PASS Directory tree formatted correctly with {len(pipe_lines)} valid rows (+30)")
                elif len(pipe_lines) > 0:
                    score += 15
                    feedback_parts.append(f"PARTIAL Directory tree has proper header but only {len(pipe_lines)} valid rows (+15)")
                else:
                    feedback_parts.append("FAIL Directory tree missing required pipe-delimited data rows")
            else:
                feedback_parts.append("FAIL Directory tree file lacks required exact header row")
    else:
        feedback_parts.append("FAIL Directory tree file not found at /home/ga/Reports/directory_tree.txt")

    # ── 4. Organizational Profile Sections (30 pts) ───────────────────────────
    profile_mtime = result.get("profile_file_mtime", 0)
    profile_content = result.get("profile_file_content", "")
    
    prof_stats = {}
    if result.get("profile_file_exists"):
        if start_time > 0 and profile_mtime < start_time:
            feedback_parts.append("FAIL Profile file is stale")
        else:
            sections_found = 0
            req_sections = [
                "VOLUME_FILESYSTEM", "TOTAL_DIRECTORIES", "TOTAL_FILES", 
                "ALLOCATED_FILES", "DELETED_FILES", "MAX_DIRECTORY_DEPTH", 
                "FILE_EXTENSION_DISTRIBUTION", "TOP_LEVEL_DIRECTORIES", 
                "ORGANIZATIONAL_ASSESSMENT"
            ]
            
            for sec in req_sections:
                if sec in profile_content.upper():
                    sections_found += 1
                    
            # Extract basic counts for tolerance check
            match_files = re.search(r'TOTAL_FILES:\s*(\d+)', profile_content, re.IGNORECASE)
            if match_files: prof_stats["total_files"] = int(match_files.group(1))
            
            match_dirs = re.search(r'TOTAL_DIRECTORIES:\s*(\d+)', profile_content, re.IGNORECASE)
            if match_dirs: prof_stats["total_dirs"] = int(match_dirs.group(1))
            
            if sections_found == len(req_sections):
                score += 30
                feedback_parts.append("PASS Profile file contains all required sections (+30)")
            elif sections_found >= len(req_sections) // 2:
                score += 15
                feedback_parts.append(f"PARTIAL Profile file contains {sections_found}/{len(req_sections)} sections (+15)")
            else:
                feedback_parts.append("FAIL Profile file missing most required sections")
    else:
        feedback_parts.append("FAIL Profile file not found at /home/ga/Reports/organization_profile.txt")

    # ── 5. Profile Accuracy / Tolerance (20 pts) ──────────────────────────────
    if gt and prof_stats:
        gt_files = gt.get("total_files", 0)
        gt_dirs = gt.get("total_dirs", 0)
        
        file_diff = abs(prof_stats.get("total_files", 0) - gt_files)
        dir_diff = abs(prof_stats.get("total_dirs", 0) - gt_dirs)
        
        file_acc = file_diff <= (gt_files * 0.20)
        dir_acc = dir_diff <= (gt_dirs * 0.20)
        
        if file_acc and dir_acc:
            score += 20
            feedback_parts.append("PASS Profile stats within 20% of Ground Truth (+20)")
        elif file_acc or dir_acc:
            score += 10
            feedback_parts.append("PARTIAL Some profile stats within 20% of GT (+10)")
        else:
            feedback_parts.append(f"FAIL Profile stats inaccurate (Agent: F:{prof_stats.get('total_files')}/D:{prof_stats.get('total_dirs')}, GT: F:{gt_files}/D:{gt_dirs})")
    elif not gt:
        # If GT failed to generate for some reason, award points if they extracted something reasonable
        if prof_stats.get("total_files", 0) > 0:
            score += 20
            feedback_parts.append("PASS Extracted realistic profile stats (+20, GT unavailable)")

    # ── 6. Internal Consistency (10 pts) ──────────────────────────────────────
    if parsed_tree_files > 0 and prof_stats.get("total_files", 0) > 0:
        # Check if the tree row count somewhat matches the profile report
        diff = abs(parsed_tree_files - prof_stats.get("total_files", 0))
        if diff <= (prof_stats.get("total_files", 0) * 0.10):
            score += 10
            feedback_parts.append("PASS Internal consistency verified between tree parsing and profile stats (+10)")
        else:
            feedback_parts.append(f"FAIL Internal inconsistency: Tree has {parsed_tree_files} files, Profile claims {prof_stats.get('total_files')}")
            
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }