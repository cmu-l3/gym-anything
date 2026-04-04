"""
Verifier for legacy_banking_migration task.

Scoring (100 points):
  - ArrayList removed from TransactionProcessor.cs:     25 pts
  - Hashtable removed from TransactionProcessor.cs:     25 pts
  - DateTime.Now removed from project:                  20 pts
  - System.Random removed (secure RNG added):           15 pts
  - StringBuilder used in report generation:            15 pts

Pass threshold: 60 points
Build gate: if build_errors > 0, score capped at 40
"""

import json
import os
import re
import shutil
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\legacy_banking_migration_result.json"
PROCESSOR_PATH = "C:\\Users\\Docker\\source\\repos\\BankingCore\\TransactionProcessor.cs"


def verify_legacy_banking_migration(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.mkdtemp(prefix="verify_banking_")
    try:
        # --- Step 1: Read export result JSON ---
        result = {}
        json_local = os.path.join(tmp, "result.json")
        try:
            copy_from_env(RESULT_PATH, json_local)
            with open(json_local, encoding="utf-8-sig") as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0,
                    "feedback": "Result JSON not found — export script may not have run"}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Cannot read result JSON: {e}"}

        # --- Anti-gaming gate: file must have been modified ---
        if not result.get("processor_modified_after_start", False):
            return {"passed": False, "score": 0,
                    "feedback": "TransactionProcessor.cs was not modified — no work detected"}

        # --- Step 2: Independently copy and analyse TransactionProcessor.cs ---
        proc_content = ""
        proc_local = os.path.join(tmp, "TransactionProcessor.cs")
        try:
            copy_from_env(PROCESSOR_PATH, proc_local)
            with open(proc_local, encoding="utf-8-sig") as f:
                proc_content = f.read()
        except Exception:
            # Fall back to export-script results only
            proc_content = ""

        def _has(pattern, content):
            return bool(re.search(pattern, content, re.IGNORECASE))

        # For each criterion, use export result as primary, independent analysis as secondary
        def merged(export_key, pattern, content, expect_absent=True):
            """Returns True if the anti-pattern is still present (or new pattern is absent)."""
            export_val = result.get(export_key)
            if content:
                independent = _has(pattern, content)
                # If export and independent disagree, trust independent analysis
                return independent
            # Fall back to export result
            if export_val is None:
                return expect_absent  # conservative default
            return bool(export_val)

        score = 0
        fb = []

        # Criterion 1 (25 pts): ArrayList removed
        still_has_arraylist = merged("has_array_list", r"new ArrayList\b", proc_content)
        if not still_has_arraylist:
            score += 25
            fb.append("ArrayList replaced with generic List<T> (+25)")
        else:
            fb.append("ArrayList still present in TransactionProcessor.cs (0/25)")

        # Criterion 2 (25 pts): Hashtable removed
        still_has_hashtable = merged("has_hashtable", r"new Hashtable\b", proc_content)
        if not still_has_hashtable:
            score += 25
            fb.append("Hashtable replaced with generic Dictionary (+25)")
        else:
            fb.append("Hashtable still present in TransactionProcessor.cs (0/25)")

        # Criterion 3 (20 pts): DateTime.Now removed
        still_has_dtnow = merged("has_datetime_now", r"DateTime\.Now\b", proc_content)
        if not still_has_dtnow:
            score += 20
            fb.append("DateTime.Now removed — using DateTimeOffset.UtcNow or equivalent (+20)")
        else:
            fb.append("DateTime.Now still present (timezone bug) (0/20)")

        # Criterion 4 (15 pts): System.Random removed for ID generation
        still_has_sysrand = merged("has_system_random", r"new Random\(\)", proc_content)
        has_secure_rng = bool(re.search(
            r"RandomNumberGenerator|RNGCryptoServiceProvider|GetInt32\b|GetBytes\b",
            proc_content, re.IGNORECASE
        )) if proc_content else result.get("has_secure_rng", False)

        if not still_has_sysrand and has_secure_rng:
            score += 15
            fb.append("System.Random replaced with cryptographic RNG (+15)")
        elif not still_has_sysrand:
            score += 8
            fb.append("System.Random removed but no cryptographic RNG found (+8)")
        else:
            fb.append("System.Random still used for transaction ID generation (0/15)")

        # Criterion 5 (15 pts): StringBuilder used in GenerateReport
        has_sb = bool(re.search(r"StringBuilder", proc_content, re.IGNORECASE)) \
            if proc_content else result.get("has_stringbuilder", False)
        if has_sb:
            score += 15
            fb.append("StringBuilder used in report generation (+15)")
        else:
            fb.append("No StringBuilder found — string concatenation loop still present (0/15)")

        # --- Build gate ---
        build_errors = result.get("build_errors", 999)
        build_success = result.get("build_success", False)
        if not build_success and build_errors > 0:
            if score > 40:
                score = 40
                fb.append(f"BUILD FAILED ({build_errors} errors) — score capped at 40")
            else:
                fb.append(f"BUILD FAILED ({build_errors} errors)")
        else:
            fb.append("Build: OK (0 errors)")

        passed = score >= 60
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(fb)
        }

    except Exception as e:
        logger.exception("Verification error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
