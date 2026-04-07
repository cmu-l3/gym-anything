#!/usr/bin/env python3
"""
Verifier for cloud_return_logical_analysis task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and DB found
  15 pts  — Logical data source added to case
  15 pts  — Ingest completed (Files populated with MD5 and MIME types)
  30 pts  — TSV catalog exists, is recent, and correctly formatted
  30 pts  — Summary text file exists, is recent, and values match Autopsy DB exactly
"""

import json
import os
import re
import tempfile

def verify_cloud_return_logical_analysis(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/cloud_return_result.json")

    # ── 1. Pull result JSON from VM ──────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env = env_info.get("copy_from_env")
        if not copy_from_env:
            return {"passed": False, "score": 0, "feedback": "Copy function not available"}
            
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — task was not attempted."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # Extract vital stats
    start_time = result.get("start_time", 0)
    db_total = result.get("db_total_files", 0)
    db_jpeg = result.get("db_jpeg_count", 0)
    db_text = result.get("db_text_count", 0)

    # ── 2. Evaluate Database State (40 points) ───────────────────────────────
    
    # Case DB (10 pts)
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # Data Source (15 pts)
    if result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Data source added (+15)")
    else:
        feedback_parts.append("FAIL Data source missing")

    # Ingest (15 pts)
    if result.get("ingest_completed") and db_total > 0:
        pts = 10
        msg = f"PASS Ingest completed ({db_total} files)"
        if result.get("db_has_hashes"):
            pts += 5
            msg += " with Hashes"
        score += pts
        feedback_parts.append(f"{msg} (+{pts})")
    else:
        feedback_parts.append("FAIL Ingest incomplete or zero files indexed")

    # ── 3. Evaluate TSV Catalog (30 points) ──────────────────────────────────
    catalog_exists = result.get("catalog_file_exists", False)
    catalog_content = result.get("catalog_content", "").replace("\\n", "\n").replace("\\t", "\t")
    catalog_mtime = result.get("catalog_mtime", 0)
    
    if catalog_exists:
        is_recent = (start_time == 0 or catalog_mtime >= start_time)
        lines = [l for l in catalog_content.splitlines() if l.strip()]
        
        has_header = any("FILENAME" in l.upper() for l in lines[:3])
        has_tabs = any("\t" in l for l in lines)
        data_lines = len([l for l in lines if "\t" in l and "FILENAME" not in l.upper()])
        
        if not is_recent:
            feedback_parts.append("FAIL Catalog file pre-dates task start (stale)")
        elif has_header and has_tabs and data_lines >= max(1, db_total // 2):
            score += 30
            feedback_parts.append(f"PASS TSV Catalog well-formatted with {data_lines} data rows (+30)")
        elif has_tabs and data_lines > 0:
            score += 15
            feedback_parts.append(f"PARTIAL TSV Catalog lacks proper header or missing rows (+15)")
        else:
            feedback_parts.append("FAIL TSV Catalog empty or lacks tab delimiters")
    else:
        feedback_parts.append("FAIL logical_catalog.tsv not found")

    # ── 4. Evaluate Summary Text (30 points) ─────────────────────────────────
    summary_exists = result.get("summary_file_exists", False)
    summary_content = result.get("summary_content", "").upper()
    summary_mtime = result.get("summary_mtime", 0)
    
    if summary_exists:
        is_recent = (start_time == 0 or summary_mtime >= start_time)
        
        if not is_recent:
            feedback_parts.append("FAIL Summary file pre-dates task start (stale)")
        else:
            # Parse numbers from agent summary
            agent_total = -1
            agent_jpeg = -1
            agent_text = -1
            
            m_total = re.search(r'TOTAL_FILES:\s*(\d+)', summary_content)
            if m_total: agent_total = int(m_total.group(1))
            
            m_jpeg = re.search(r'JPEG_IMAGES:\s*(\d+)', summary_content)
            if m_jpeg: agent_jpeg = int(m_jpeg.group(1))
                
            m_text = re.search(r'TEXT_FILES:\s*(\d+)', summary_content)
            if m_text: agent_text = int(m_text.group(1))
            
            summary_pts = 0
            
            # Check Total
            if agent_total == db_total and db_total > 0:
                summary_pts += 10
                feedback_parts.append(f"PASS Summary Total ({agent_total}) matches DB (+10)")
            elif agent_total >= 0:
                feedback_parts.append(f"FAIL Summary Total ({agent_total}) != DB ({db_total})")
                
            # Check JPEGs
            if agent_jpeg == db_jpeg and db_jpeg > 0:
                summary_pts += 10
                feedback_parts.append(f"PASS Summary JPEGs ({agent_jpeg}) matches DB (+10)")
            elif agent_jpeg >= 0:
                feedback_parts.append(f"FAIL Summary JPEGs ({agent_jpeg}) != DB ({db_jpeg})")
                
            # Check Text
            if agent_text == db_text and db_text > 0:
                summary_pts += 10
                feedback_parts.append(f"PASS Summary Text ({agent_text}) matches DB (+10)")
            elif agent_text >= 0:
                feedback_parts.append(f"FAIL Summary Text ({agent_text}) != DB ({db_text})")
                
            if summary_pts == 0 and agent_total == -1:
                feedback_parts.append("FAIL Summary file lacks required formatted lines")
            
            score += summary_pts
    else:
        feedback_parts.append("FAIL cloud_summary.txt not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }