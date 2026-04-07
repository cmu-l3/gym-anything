#!/usr/bin/env python3
import json
import os
import tempfile

def verify_nested_archive_triage(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/nested_archive_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/nested_archive_gt.json")
    copy_from_env = env_info.get("copy_from_env")

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Pull result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # Pull GT
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    # Criterion 1: DB found (10 pts)
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # Criterion 2: Embedded extraction (20 pts)
    extracted = result.get("extracted_files", [])
    required_files = ["payloads.zip", "vm_disk_01.dd", "usb_clone.dd"]
    extracted_count = sum(1 for f in required_files if f in extracted)
    
    if extracted_count == 3:
        score += 20
        feedback_parts.append("PASS All embedded files extracted and found in DB (+20)")
    elif extracted_count > 0:
        score += 10
        feedback_parts.append(f"PARTIAL Some embedded files extracted ({extracted_count}/3) (+10)")
    else:
        feedback_parts.append("FAIL No embedded files extracted (Embedded File Extractor module may not have run)")

    # Criterion 3: Payloads exported (20 pts)
    exports = result.get("exports_found", [])
    if "vm_disk_01.dd" in exports and "usb_clone.dd" in exports:
        score += 20
        feedback_parts.append("PASS Both payloads exported to local directory (+20)")
    elif len(exports) > 0:
        score += 10
        feedback_parts.append("PARTIAL One payload exported (+10)")
    else:
        feedback_parts.append("FAIL Payloads not exported to correct directory")

    # Criterion 4: Payload re-ingested (20 pts)
    image_names = result.get("image_names", [])
    data_sources = result.get("data_sources", [])
    reingested = False
    
    # Check if the disk image path was explicitly added to tsk_image_names
    for name in image_names:
        if "vm_disk_01.dd" in name:
            reingested = True
            break
            
    if reingested:
        score += 20
        feedback_parts.append("PASS vm_disk_01.dd was successfully re-ingested as a Disk Image data source (+20)")
    else:
        feedback_parts.append("FAIL vm_disk_01.dd was not re-ingested as a Disk Image data source")

    # Criterion 5: Hash Provenance Report (30 pts)
    if result.get("report_exists"):
        content = result.get("report_content", "")
        lines = [l.strip() for l in content.splitlines() if l.strip()]
        
        parsed_hashes = {}
        for line in lines:
            if "|" in line:
                parts = line.split("|")
                if len(parts) >= 2:
                    parsed_hashes[parts[0].strip()] = parts[1].strip().lower()
                    
        matches = 0
        for k, expected_hash in gt.items():
            if k in parsed_hashes and parsed_hashes[k] == expected_hash:
                matches += 1
                
        if matches == 4:
            score += 30
            feedback_parts.append("PASS Report contains all 4 correct MD5 hashes (+30)")
        elif matches > 0:
            score += int(matches * 7.5)
            feedback_parts.append(f"PARTIAL Report contains {matches}/4 correct hashes (+{int(matches * 7.5)})")
        else:
            feedback_parts.append("FAIL Report exists but contains no correct hashes")
    else:
        feedback_parts.append("FAIL Hash provenance report not found")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }