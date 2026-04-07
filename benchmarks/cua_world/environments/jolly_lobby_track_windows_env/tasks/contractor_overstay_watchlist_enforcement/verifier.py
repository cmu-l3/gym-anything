#!/usr/bin/env python3
"""
Verifier for contractor_overstay_watchlist_enforcement task.

This is a stub verifier. Full evaluation is done externally via VLM checklist.
Basic programmatic checks are included for file existence and content validation.

Scoring (100 points total):
  - 5 pts: Compliance report file exists on Desktop
  - 5 pts: File was created during the task window (anti-gaming)
  - 10 pts each (x5): Each of the 5 violators present in report (50 pts total)
  - 15 pts: Tier keywords (WARNING, SUSPENDED, BANNED) present
  - 10 pts: Duration information present in report
  - 15 pts: No false positives (non-violating contractors absent)

Pass threshold: score >= 70

Ground truth — December 2025 contractors exceeding 120 minutes:
  1. Alex Rivera    / Siemens AG       / 09:00-11:15 = 135 min -> WARNING
  2. Maria Garcia   / Deloitte LLP     / 10:00-12:30 = 150 min -> SUSPENDED
  3. Margaret Allen / IBM Corporation  / 10:00-12:30 = 150 min -> SUSPENDED
  4. Jessica Harris / ExxonMobil       / 08:30-11:30 = 180 min -> BANNED
  5. Rachel Kim     / McKinsey & Co    / 08:30-12:00 = 210 min -> BANNED
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_contractor_overstay_watchlist_enforcement(traj, env_info, task_info):
    """Verify the contractor overstay watchlist enforcement task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        # Step 1: Load the exported result JSON from the VM
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env(
                "/tmp/contractor_overstay_watchlist_enforcement_result.json",
                temp_json.name,
            )
            with open(temp_json.name, "r") as f:
                result = json.load(f)
        finally:
            os.unlink(temp_json.name)

        # PREREQUISITE: Output file must exist
        if not result.get("output_exists", False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Compliance report watchlist_enforcement_dec2025.csv not found on Desktop.",
            }

        # Step 2: Get file content — prefer independent copy, fall back to embedded
        content = ""
        try:
            temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
            copy_from_env(
                "C:/Users/Docker/Desktop/watchlist_enforcement_dec2025.csv",
                temp_csv.name,
            )
            with open(temp_csv.name, "r", encoding="utf-8", errors="replace") as f:
                content = f.read(10000)
            os.unlink(temp_csv.name)
        except Exception as e:
            logger.warning(f"Independent file copy failed: {e}")
            content = result.get("output_content", "")

        content_lower = content.lower()

        score = 0
        feedback_parts = []

        # --- File existence (5 pts) ---
        score += 5
        feedback_parts.append("Report file exists")

        # --- Anti-gaming: file created during task (5 pts) ---
        task_start = result.get("task_start_time", 0)
        file_write = result.get("output_last_write", 0)
        if task_start and file_write and file_write >= task_start:
            score += 5
            feedback_parts.append("File created during task")
        elif task_start and file_write:
            feedback_parts.append("WARNING: File may predate task start")
        else:
            # Can't verify timing, give benefit of doubt
            score += 5

        # --- Violator presence checks (10 pts each, 50 pts total) ---
        violators = [
            ("Alex Rivera", "rivera", "siemens"),
            ("Maria Garcia", "garcia", "deloitte"),
            ("Margaret Allen", "allen", "ibm"),
            ("Jessica Harris", "harris", "exxon"),
            ("Rachel Kim", "rachel", "mckinsey"),
        ]
        found_count = 0
        for display_name, name_key, company_key in violators:
            if name_key in content_lower or company_key in content_lower:
                score += 10
                found_count += 1
                feedback_parts.append(f"{display_name}: FOUND")
            else:
                feedback_parts.append(f"{display_name}: NOT FOUND")

        # --- Tier keywords present (15 pts) ---
        tiers_found = []
        for tier in ["warning", "suspended", "banned"]:
            if tier in content_lower:
                tiers_found.append(tier.upper())
        if len(tiers_found) >= 3:
            score += 15
            feedback_parts.append(f"All enforcement tiers present: {tiers_found}")
        elif len(tiers_found) >= 1:
            score += 5
            feedback_parts.append(f"Partial tiers found: {tiers_found}")
        else:
            feedback_parts.append("No enforcement tier keywords found")

        # --- Duration information present (10 pts) ---
        duration_markers = ["135", "150", "180", "210", "duration", "minutes", "min"]
        durations_found = [d for d in duration_markers if d in content_lower]
        if len(durations_found) >= 2:
            score += 10
            feedback_parts.append("Duration information present")
        elif len(durations_found) >= 1:
            score += 5
            feedback_parts.append("Partial duration information")
        else:
            feedback_parts.append("No duration information found")

        # --- False positive check (15 pts) ---
        # Non-violating contractors should NOT appear in the report
        false_positives = [
            "jennifer jones",
            "linda davis",
            "joseph thomas",
            "daniel robinson",
            "lisa lewis",
            "ashley hernandez",
            "donna wright",
            "paul nelson",
            "emily perez",
        ]
        fps_found = [fp for fp in false_positives if fp in content_lower]
        if not fps_found:
            score += 15
            feedback_parts.append("No false positives detected")
        elif len(fps_found) <= 2:
            score += 5
            feedback_parts.append(f"Minor false positives: {fps_found}")
        else:
            feedback_parts.append(f"False positives found: {fps_found}")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {
                "violators_found": found_count,
                "tiers_found": tiers_found,
                "false_positives": fps_found if fps_found else [],
                "file_size_bytes": result.get("output_size", 0),
                "content_preview": content[:500] if content else "",
            },
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result JSON not found — export_result.ps1 may not have run.",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}",
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
