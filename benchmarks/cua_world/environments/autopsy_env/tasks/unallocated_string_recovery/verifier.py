#!/usr/bin/env python3
"""
Verifier for unallocated_string_recovery task.

Uses `copy_from_env` to securely transfer pre-computed json records and prevents tampering.
Checks multiple conditions independently (Total Score: 100).
"""

import json
import os
import re
import tempfile

def verify_unallocated_string_recovery(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/string_recovery_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/string_recovery_gt.json")

    # Fetch result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # Fetch GT JSON
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

    # 1-3. Autopsy DB Checks (25 Points)
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not found")

    if result.get("ingest_completed"):
        score += 5
        feedback_parts.append("PASS Ingest completed (+5)")
    else:
        feedback_parts.append("FAIL Ingest not completed")

    # 4-6. Raw Strings Validation (30 Points)
    start_time = result.get("start_time", 0)
    if result.get("raw_strings_exists"):
        mtime = result.get("raw_strings_mtime", 0)
        if start_time == 0 or mtime >= start_time:
            score += 10
            feedback_parts.append("PASS Raw strings file is recent (+10)")
        else:
            feedback_parts.append("FAIL Raw strings file is stale (likely pre-task)")
            
        line_count = result.get("raw_strings_line_count", 0)
        gt_total = gt.get("total_strings", 0)
        if gt_total > 0:
            if abs(line_count - gt_total) / gt_total <= 0.3:
                score += 10
                feedback_parts.append(f"PASS Raw string count {line_count} within 30% of GT {gt_total} (+10)")
            elif line_count > 0:
                score += 5
                feedback_parts.append(f"PARTIAL Raw string count {line_count} vs GT {gt_total} (+5)")
        elif line_count > 0:
            score += 10
            feedback_parts.append("PASS Raw strings exist (+10, no GT available)")
                
        samples = gt.get("sample_strings", [])
        if samples:
            raw_content = result.get("raw_strings_content", "").lower()
            found = sum(1 for s in samples if s.lower() in raw_content)
            if found >= len(samples) / 2:
                score += 10
                feedback_parts.append(f"PASS Found {found}/{len(samples)} GT sample strings in extraction (+10)")
            else:
                feedback_parts.append(f"FAIL Only {found}/{len(samples)} GT sample strings found in extraction")
        else:
            score += 10
    else:
        feedback_parts.append("FAIL Raw strings file missing")

    # 7. Classification Structure Validation (10 points)
    class_content = result.get("classification_content", "")
    if result.get("classification_exists"):
        sections = [
            "FILE_PATHS", "POTENTIAL_URLS", "EMAIL_PATTERNS", "NUMERIC_DATA",
            "DOCUMENT_FRAGMENTS", "NTFS_ARTIFACTS", "OTHER_NOTABLE"
        ]
        found_sections = [s for s in sections if s in class_content.upper()]
        if len(found_sections) == len(sections):
            score += 10
            feedback_parts.append("PASS Classification file has all 7 sections (+10)")
        else:
            pts = int(10 * len(found_sections) / len(sections))
            score += pts
            feedback_parts.append(f"PARTIAL Classification file has {len(found_sections)}/7 sections (+{pts})")
    else:
        feedback_parts.append("FAIL Classification file missing")

    # 8-11. Summary Report Metrics & Count Extraction (35 points)
    summary_content = result.get("summary_content", "")
    if result.get("summary_exists"):
        fields = [
            "TOTAL_STRINGS_EXTRACTED", "UNIQUE_STRINGS", "UNALLOCATED_BYTES_EXAMINED",
            "FILE_PATH_COUNT", "URL_COUNT", "EMAIL_COUNT", "NUMERIC_COUNT",
            "DOCUMENT_FRAGMENT_COUNT", "NTFS_ARTIFACT_COUNT"
        ]
        found_fields = [f for f in fields if f in summary_content.upper()]
        if len(found_fields) == len(fields):
            score += 10
            feedback_parts.append("PASS Summary file has all 9 metrics (+10)")
        else:
            pts = int(10 * len(found_fields) / len(fields))
            score += pts
            feedback_parts.append(f"PARTIAL Summary file has {len(found_fields)}/9 fields (+{pts})")

        # Utility to extract digits adjacent to specific fields
        def extract_count(field):
            m = re.search(fr"{field}[^\d]*(\d+)", summary_content, re.IGNORECASE)
            return int(m.group(1)) if m else None

        # 10. Summary values vs GT totals
        tot_ext = extract_count("TOTAL_STRINGS_EXTRACTED")
        uniq_str = extract_count("UNIQUE_STRINGS")
        unalloc = extract_count("UNALLOCATED_BYTES_EXAMINED")
        
        gt_tot = gt.get("total_strings", 0)
        gt_uniq = gt.get("unique_strings", 0)
        gt_unalloc = gt.get("unallocated_bytes", 0)

        matches_tot = 0
        if tot_ext is not None and gt_tot > 0 and abs(tot_ext - gt_tot)/gt_tot <= 0.3: matches_tot += 1
        if uniq_str is not None and gt_uniq > 0 and abs(uniq_str - gt_uniq)/gt_uniq <= 0.3: matches_tot += 1
        if unalloc is not None and gt_unalloc > 0 and abs(unalloc - gt_unalloc)/gt_unalloc <= 0.3: matches_tot += 1

        if matches_tot == 3:
            score += 10
            feedback_parts.append("PASS Summary global totals perfectly match GT (+10)")
        else:
            pts = int(10 * matches_tot / 3)
            score += pts
            feedback_parts.append(f"PARTIAL Summary global totals match {matches_tot}/3 (+{pts})")

        # 8. Category Classification counts
        gt_metrics = [
            ("FILE_PATH_COUNT", gt.get("file_path_count", 0)),
            ("URL_COUNT", gt.get("url_count", 0)),
            ("EMAIL_COUNT", gt.get("email_count", 0)),
            ("NUMERIC_COUNT", gt.get("numeric_count", 0)),
            ("DOCUMENT_FRAGMENT_COUNT", gt.get("doc_fragment_count", 0)),
            ("NTFS_ARTIFACT_COUNT", gt.get("ntfs_artifact_count", 0)),
        ]
        
        matches_class = 0
        for fld, gt_val in gt_metrics:
            val = extract_count(fld)
            if val is not None:
                # Within generous 50% boundary for ambiguous regex tasks
                if gt_val == 0 and val == 0:
                    matches_class += 1
                elif gt_val > 0 and abs(val - gt_val)/gt_val <= 0.5:
                    matches_class += 1
                    
        if matches_class == 6:
            score += 10
            feedback_parts.append("PASS All string classification counts align well with GT (+10)")
        else:
            pts = int(10 * matches_class / 6)
            score += pts
            feedback_parts.append(f"PARTIAL Classification counts matching GT: {matches_class}/6 (+{pts})")

        # 11. Narrative Forensic assessment verification
        if "FORENSIC_ASSESSMENT" in summary_content.upper():
            idx = summary_content.upper().find("FORENSIC_ASSESSMENT")
            assessment = summary_content[idx+len("FORENSIC_ASSESSMENT"):].strip()
            if len(assessment) >= 20:
                score += 5
                feedback_parts.append("PASS Forensic assessment present and sufficient length (+5)")
            else:
                feedback_parts.append("FAIL Forensic assessment is too short or malformed")
        else:
            feedback_parts.append("FAIL No forensic assessment section found in summary")
    else:
        feedback_parts.append("FAIL Summary file missing")

    # Hard threshold failure logic
    passed = score >= 60 and result.get("raw_strings_exists") and result.get("case_db_found")
    return {
        "passed": passed, 
        "score": score, 
        "feedback": " | ".join(feedback_parts)
    }