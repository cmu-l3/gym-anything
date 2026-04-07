#!/usr/bin/env python3
"""
Verifier for disk_partition_triage task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case DB found
  10 pts  — Disk image added as data source
  5 pts   — Ingest completed (files indexed)
  10 pts  — FILE_SYSTEM_TYPE matches GT exactly (e.g., NTFS)
  5 pts   — IMAGE_SIZE_BYTES within 1% of GT
  10 pts  — SECTOR_SIZE & CLUSTER_SIZE correct
  5 pts   — TOTAL_SECTORS & TOTAL_CLUSTERS within 5% of GT
  5 pts   — VOLUME_NAME correct
  10 pts  — PARTITION_TABLE structure present
  5 pts   — Partition offset matches expected (or 0 if unpartitioned)
  5 pts   — FILE_STATISTICS section present
  10 pts  — TOTAL_FILES & DELETED_FILES within 20% of GT
  10 pts  — Triage summary exists, is >= 3 sentences, and mentions file system
"""

import json
import os
import re
import tempfile

def extract_val(text, key):
    """Extract string value matching 'KEY: value' from text."""
    m = re.search(rf"{re.escape(key)}:\s*(.+)", text, re.IGNORECASE)
    return m.group(1).strip() if m else None

def extract_num(text, key):
    """Extract numeric value from 'KEY: value'."""
    val = extract_val(text, key)
    if not val: return None
    # Strip any non-numeric characters except digits, periods, and minus
    val_clean = re.sub(r'[^\d.-]', '', val)
    try:
        return float(val_clean)
    except ValueError:
        return None

def verify_disk_partition_triage(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/disk_triage_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/disk_triage_gt.json")

    # ── Pull result JSON from VM ──────────────────────────────────────────────
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
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # ── Pull ground truth from VM ──────────────────────────────────────────────
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    # GT Defaults if missing
    gt_fs = gt.get("file_system_type", "NTFS").upper()
    gt_size = gt.get("image_size_bytes", 6291456)
    gt_sec = gt.get("sector_size", 512)
    gt_clus = gt.get("cluster_size", 512)
    gt_tot_sec = gt.get("total_sectors", 12288)
    gt_tot_clus = gt.get("total_clusters", 12288)
    gt_vol = gt.get("volume_name", "NONE").upper()
    gt_tot_files = gt.get("total_files", 40)
    gt_del_files = gt.get("deleted_files", 10)
    
    gt_offsets = [p.get("offset", 0) for p in gt.get("partitions", [])]
    if not gt_offsets: gt_offsets = [0] # Raw partition backup

    # ── Criteria 1-3: Autopsy Case State (25 pts) ─────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not found in DB")

    if result.get("ingest_completed"):
        score += 5
        feedback_parts.append("PASS Ingest completed (+5)")

    # ── Parse Agent Report ────────────────────────────────────────────────────
    report = result.get("report_content", "")
    start_time = result.get("start_time", 0)
    rep_mtime = result.get("report_mtime", 0)
    
    if not result.get("report_file_exists") or (rep_mtime < start_time and start_time > 0):
        feedback_parts.append("FAIL Triage report missing or stale")
        return {"passed": score >= 60, "score": score, "feedback": " | ".join(feedback_parts)}

    # ── Criterion 4: File System Type (10 pts) ────────────────────────────────
    rep_fs = extract_val(report, "FILE_SYSTEM_TYPE")
    if rep_fs and gt_fs in rep_fs.upper():
        score += 10
        feedback_parts.append(f"PASS FS Type ({rep_fs}) (+10)")
    else:
        feedback_parts.append(f"FAIL FS Type: got {rep_fs}, expected {gt_fs}")

    # ── Criterion 5: Image Size (5 pts) ───────────────────────────────────────
    rep_size = extract_num(report, "IMAGE_SIZE_BYTES")
    if rep_size is not None and abs(rep_size - gt_size) / max(1, gt_size) < 0.05:
        score += 5
        feedback_parts.append("PASS Image Size (+5)")
    else:
        feedback_parts.append(f"FAIL Image Size: got {rep_size}, expected {gt_size}")

    # ── Criterion 6: Sector / Cluster Sizes (10 pts) ──────────────────────────
    rep_sec = extract_num(report, "SECTOR_SIZE")
    rep_clus = extract_num(report, "CLUSTER_SIZE")
    sz_score = 0
    if rep_sec is not None and rep_sec == gt_sec: sz_score += 5
    if rep_clus is not None and rep_clus == gt_clus: sz_score += 5
    if sz_score > 0:
        score += sz_score
        feedback_parts.append(f"PASS Sector/Cluster Size (+{sz_score})")
    else:
        feedback_parts.append("FAIL Sector/Cluster Size mismatch")

    # ── Criterion 7: Total Sectors / Clusters (5 pts) ─────────────────────────
    rep_tsec = extract_num(report, "TOTAL_SECTORS")
    rep_tclus = extract_num(report, "TOTAL_CLUSTERS")
    if (rep_tsec and gt_tot_sec and abs(rep_tsec - gt_tot_sec) / gt_tot_sec < 0.1) or \
       (rep_tclus and gt_tot_clus and abs(rep_tclus - gt_tot_clus) / gt_tot_clus < 0.1):
        score += 5
        feedback_parts.append("PASS Total Sectors/Clusters (+5)")

    # ── Criterion 8: Volume Name (5 pts) ──────────────────────────────────────
    rep_vol = extract_val(report, "VOLUME_NAME")
    if rep_vol and (rep_vol.upper() == gt_vol or (gt_vol=="NONE" and not rep_vol.strip())):
        score += 5
        feedback_parts.append("PASS Volume Name (+5)")

    # ── Criterion 9: Partition Table Present (10 pts) ─────────────────────────
    if "PARTITION_TABLE" in report.upper():
        score += 10
        feedback_parts.append("PASS Partition table header present (+10)")
        
        # ── Criterion 10: Partition Offsets (5 pts)
        pipe_lines = [l for l in report.splitlines() if '|' in l]
        matched_offset = False
        for pline in pipe_lines:
            parts = [p.strip() for p in pline.split('|')]
            if len(parts) >= 2 and parts[1].isdigit():
                offset = int(parts[1])
                if offset in gt_offsets or offset == 0:
                    matched_offset = True
        
        if matched_offset or len(pipe_lines) > 0:
            score += 5
            feedback_parts.append("PASS Partition offsets valid (+5)")
    else:
        feedback_parts.append("FAIL Partition table missing")

    # ── Criterion 11: File Statistics Present (5 pts) ─────────────────────────
    if "FILE_STATISTICS" in report.upper():
        score += 5
        feedback_parts.append("PASS File statistics header present (+5)")
        
        # ── Criterion 12: File Counts Accuracy (10 pts)
        rep_totf = extract_num(report, "TOTAL_FILES")
        rep_delf = extract_num(report, "DELETED_FILES")
        stat_score = 0
        
        if rep_totf is not None and gt_tot_files > 0 and abs(rep_totf - gt_tot_files)/gt_tot_files < 0.25:
            stat_score += 5
        elif rep_totf is not None and rep_totf > 0:
            stat_score += 2
            
        if rep_delf is not None and gt_del_files > 0 and abs(rep_delf - gt_del_files)/gt_del_files < 0.3:
            stat_score += 5
        elif rep_delf is not None and rep_delf > 0:
            stat_score += 2
            
        score += stat_score
        feedback_parts.append(f"PASS File counts accuracy (+{stat_score})")

    # ── Criterion 13: Triage Summary (10 pts) ─────────────────────────────────
    summary = result.get("summary_content", "")
    if result.get("summary_file_exists") and len(summary.strip()) > 10:
        sentences = [s.strip() for s in re.split(r'[.!?]+', summary) if s.strip()]
        has_fs = gt_fs.upper() in summary.upper() or "NTFS" in summary.upper() or "FAT" in summary.upper()
        
        if len(sentences) >= 3 and has_fs:
            score += 10
            feedback_parts.append("PASS Summary complete (+10)")
        elif len(sentences) > 0:
            score += 5
            feedback_parts.append("PARTIAL Summary incomplete or missing FS reference (+5)")
    else:
        feedback_parts.append("FAIL Triage summary missing")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }