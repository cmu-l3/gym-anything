#!/usr/bin/env python3
"""
Verifier for known_hash_identification task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and DB found
  15 pts  — Hash set successfully imported and used (seen in Autopsy DB hits)
  15 pts  — Disk image data source added
  10 pts  — Ingest completed with hash hits
  15 pts  — Hits report exists, is recent, and is properly pipe-delimited
  15 pts  — Report content accurately reflects ground-truth matching MD5s (no decoys)
  20 pts  — Summary file exists with exact required statistics correctly calculated
"""

import json
import os
import re
import tempfile


def verify_known_hash_identification(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/known_hash_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/known_hash_gt.json")

    # ── 1. Pull Result JSON ───────────────────────────────────────────────────
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

    # ── 2. Pull Ground Truth ──────────────────────────────────────────────────
    gt = {
        "total_hashes": 0,
        "matching_md5s": [],
        "decoy_md5s": [],
        "matching_files": []
    }
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_matching = set([m.lower() for m in gt.get("matching_md5s", [])])
    gt_decoys = set([d.lower() for d in gt.get("decoy_md5s", [])])
    gt_total = gt.get("total_hashes", 0)

    # ── Criterion 1: Case DB Found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found for Hash_Lookup_2024 (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2 & 3: Data Source & Hash Hits in DB (15 + 15 + 10 = 40) ────
    if result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Disk image added as data source (+15)")
    else:
        feedback_parts.append("FAIL Data source not added")

    db_hits = result.get("db_hash_hits", [])
    if db_hits:
        score += 10
        feedback_parts.append(f"PASS Ingest completed with {len(db_hits)} hash hits (+10)")
        
        # Check if the required hash set name was used
        used_sets = set([h.get("set_name") for h in db_hits if h.get("set_name")])
        if "FraudRing_Hashes" in used_sets:
            score += 15
            feedback_parts.append("PASS 'FraudRing_Hashes' hash set used and generated hits (+15)")
        else:
            feedback_parts.append(f"FAIL Hits generated, but hash set name was {used_sets} instead of 'FraudRing_Hashes'")
    elif result.get("ingest_completed"):
        feedback_parts.append("FAIL Ingest completed but NO hash hits found. Hash set may not have been configured correctly.")
    else:
        feedback_parts.append("FAIL Ingest did not complete.")

    # ── Criterion 4: Hits Report Format & Content (15 + 15 = 30 pts) ──────────
    start_time = result.get("start_time", 0)
    rep_mtime = result.get("report_mtime", 0)
    rep_content = result.get("report_content", "").strip()
    
    reported_md5s = set()
    has_decoys = False
    
    if result.get("report_file_exists"):
        if start_time > 0 and rep_mtime < start_time:
            feedback_parts.append("FAIL Hits report exists but is stale (predates task start).")
        else:
            lines = [l.strip() for l in rep_content.splitlines() if l.strip()]
            pipe_lines = [l for l in lines if "|" in l]
            
            if len(pipe_lines) > 0:
                score += 15
                feedback_parts.append(f"PASS Hits report has {len(pipe_lines)} pipe-delimited entries (+15)")
                
                # Extract MD5s from the first column
                for l in pipe_lines:
                    cols = [c.strip() for c in l.split("|")]
                    if len(cols) >= 1:
                        md5_cand = cols[0].lower()
                        if re.match(r'^[a-f0-9]{32}$', md5_cand):
                            reported_md5s.add(md5_cand)
                
                # Compare to Ground Truth
                valid_hits = reported_md5s.intersection(gt_matching)
                decoy_hits = reported_md5s.intersection(gt_decoys)
                
                if len(valid_hits) >= len(gt_matching) and len(gt_matching) > 0:
                    if len(decoy_hits) == 0:
                        score += 15
                        feedback_parts.append("PASS Report contains all true hash hits and NO decoys (+15)")
                    else:
                        score += 5
                        feedback_parts.append(f"PARTIAL Report contains true hits but falsely flagged {len(decoy_hits)} decoys (+5)")
                elif len(valid_hits) > 0:
                    score += 8
                    feedback_parts.append(f"PARTIAL Report missing some true hits ({len(valid_hits)}/{len(gt_matching)}) (+8)")
                else:
                    feedback_parts.append("FAIL Report does not contain the expected MD5 hashes.")
            else:
                feedback_parts.append("FAIL Hits report exists but is not pipe-delimited.")
    else:
        feedback_parts.append("FAIL Hits report not found at /home/ga/Reports/hash_hits_report.txt")

    # ── Criterion 5: Summary File Stats (20 pts) ──────────────────────────────
    sum_exists = result.get("summary_file_exists")
    sum_content = result.get("summary_content", "").upper()
    
    if sum_exists:
        # Check required keys
        has_set = "FRAUDRING_HASHES" in sum_content
        has_total = "TOTAL_HASHES_IN_SET:" in sum_content
        has_with = "HASHES_WITH_MATCHES:" in sum_content
        has_without = "HASHES_WITHOUT_MATCHES:" in sum_content
        
        if has_set and has_total and has_with and has_without:
            score += 10
            feedback_parts.append("PASS Summary file contains required structured fields (+10)")
            
            # Extract numbers
            try:
                m_tot = re.search(r'TOTAL_HASHES_IN_SET:\s*(\d+)', sum_content)
                m_with = re.search(r'HASHES_WITH_MATCHES:\s*(\d+)', sum_content)
                m_wout = re.search(r'HASHES_WITHOUT_MATCHES:\s*(\d+)', sum_content)
                
                if m_tot and m_with and m_wout:
                    v_tot = int(m_tot.group(1))
                    v_with = int(m_with.group(1))
                    v_wout = int(m_wout.group(1))
                    
                    if v_tot == gt_total and v_with == len(gt_matching) and v_wout == len(gt_decoys):
                        score += 10
                        feedback_parts.append("PASS Summary statistics exactly match ground truth (+10)")
                    elif v_tot == (v_with + v_wout):
                        score += 5
                        feedback_parts.append("PARTIAL Summary statistics math is correct but numbers differ from GT (+5)")
                    else:
                        feedback_parts.append("FAIL Summary statistics math is incorrect (with + without != total)")
            except Exception:
                feedback_parts.append("FAIL Failed to parse numbers from summary file.")
        else:
            feedback_parts.append("FAIL Summary file is missing one or more required fields.")
    else:
        feedback_parts.append("FAIL Summary file not found.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }