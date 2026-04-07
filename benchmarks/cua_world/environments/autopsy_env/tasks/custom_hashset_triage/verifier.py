#!/usr/bin/env python3
"""
Verifier for custom_hashset_triage task.

Scoring (100 pts total, pass threshold = 70):
  10 pts  - Case DB found
  25 pts  - TSK_HASHSET_HIT artifacts exist mapping to 'Intel_Targets' hashset
  25 pts  - Exported files have MD5s matching the intelligence targets
  20 pts  - Report exists and has correct format
  20 pts  - Successful global custom hashset creation (verified implicitly by hit population)
"""

import json
import os
import tempfile

def verify_custom_hashset_triage(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/custom_hashset_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/custom_hashset_gt.json")

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
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run."}
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

    gt_targets = set(gt.get("targets", []))
    gt_matches = gt.get("matches", {})

    # 1. DB and Case
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # 2. Hashset Artifacts
    hashset_names = result.get("db_hashset_names", [])
    if "Intel_Targets".lower() in [n.lower() for n in hashset_names]:
        score += 25
        feedback_parts.append("PASS TSK_HASHSET_HIT artifacts found for 'Intel_Targets' (+25)")
    elif result.get("db_hashset_hits", 0) > 0:
        score += 15
        feedback_parts.append(f"PARTIAL Hashset hits found but under different name: {hashset_names} (+15)")
    else:
        feedback_parts.append("FAIL No TSK_HASHSET_HIT artifacts found in DB. Did you mark the Hash Set as 'Notable'?")

    # 3. Exported files verify against targets
    exported_md5s = result.get("exported_md5s", [])
    if not exported_md5s:
        feedback_parts.append("FAIL No files exported to Hit_Exports directory")
    else:
        valid_exports = [md5 for md5 in exported_md5s if md5 in gt_targets]
        if len(valid_exports) > 0:
            export_score = min(25, int(25 * len(valid_exports) / max(1, len(gt_matches))))
            score += export_score
            feedback_parts.append(f"PASS {len(valid_exports)} exported files match GT hashes (+{export_score})")
            
            invalid_exports = len(exported_md5s) - len(valid_exports)
            if invalid_exports > 0:
                feedback_parts.append(f"WARNING {invalid_exports} exported files did NOT match GT hashes")
        else:
            feedback_parts.append("FAIL Exported files did not match any target intel hashes")

    # 4. Report
    report_content = result.get("report_content", "").upper()
    if result.get("report_exists") and report_content.strip():
        has_case = "INV-TGT-009" in report_content
        has_hits = "TOTAL_HITS" in report_content or "TOTAL HITS" in report_content
        has_match = "HIT:" in report_content or any(h.upper() in report_content for h in gt_targets)

        if has_case and has_hits and has_match:
            score += 20
            feedback_parts.append("PASS Report format is correct (+20)")
        elif has_hits or has_match:
            score += 10
            feedback_parts.append("PARTIAL Report exists but format is incomplete (+10)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Report exists but missing required fields (+5)")
    else:
        feedback_parts.append("FAIL target_hit_report.txt not found or empty")

    # 5. Global Custom Hashset Check
    if result.get("db_hashset_hits", 0) > 0:
        score += 20
        feedback_parts.append("PASS Custom Hashset creation verified via DB hits (+20)")
    else:
        feedback_parts.append("FAIL Custom Hashset usage could not be verified")

    passed = score >= 70 and ("Intel_Targets".lower() in [n.lower() for n in hashset_names] or result.get("db_hashset_hits", 0) > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }