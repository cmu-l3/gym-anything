#!/usr/bin/env python3
"""
Verifier for contractor_overstay_audit_dec2025 task.

Scoring (100 points total):
- Prerequisite: File /home/ga/Desktop/contractor_overstay_dec2025.csv exists (else score=0)
- Criterion 1: Maria Garcia / Deloitte LLP present in report — 25 pts
- Criterion 2: Jessica Harris / ExxonMobil present in report — 25 pts
- Criterion 3: Margaret Allen / IBM Corporation present in report — 25 pts
- Criterion 4: Duration/time information present in report — 25 pts

Passing threshold: 70 points (3+ criteria met)

Ground truth (December 2025 contractors staying >120 min):
  1. Maria Garcia  / Deloitte LLP     / Finance     / 10:00-12:30 = 150 min
  2. Jessica Harris / ExxonMobil      / Environmental / 08:30-11:30 = 180 min
  3. Margaret Allen / IBM Corporation / IT Strategy  / 10:00-12:30 = 150 min
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_contractor_overstay_audit_dec2025(traj, env_info, task_info):
    """Verify the December 2025 contractor overstay compliance audit report."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        # Step 1: Copy the exported result JSON
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env(
                "/tmp/contractor_overstay_audit_dec2025_result.json", temp_json.name
            )
            with open(temp_json.name, "r") as f:
                result = json.load(f)
        finally:
            os.unlink(temp_json.name)

        # PREREQUISITE: The output file must exist
        if not result.get("file_exists", False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Output file /home/ga/Desktop/contractor_overstay_dec2025.csv not found. Agent did not create the compliance report.",
            }

        # Step 2: Independently copy the actual output file for anti-tamper verification
        content = result.get("file_content", "")
        try:
            temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
            copy_from_env(
                "/home/ga/Desktop/contractor_overstay_dec2025.csv", temp_csv.name
            )
            with open(temp_csv.name, "r", encoding="utf-8", errors="replace") as f:
                content = f.read(6000)
            os.unlink(temp_csv.name)
            logger.info("Used independently-copied file content for verification")
        except Exception as e:
            logger.warning(f"Independent file copy failed, using JSON-embedded content: {e}")

        content_lower = content.lower()

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Maria Garcia / Deloitte LLP (25 points)
        has_garcia = "garcia" in content_lower or "deloitte" in content_lower
        if has_garcia:
            score += 25
            subscores["garcia_deloitte"] = True
            feedback_parts.append("Maria Garcia / Deloitte LLP: FOUND")
        else:
            subscores["garcia_deloitte"] = False
            feedback_parts.append("Maria Garcia / Deloitte LLP: NOT FOUND")

        # Criterion 2: Jessica Harris / ExxonMobil (25 points)
        has_harris = "harris" in content_lower or "exxon" in content_lower
        if has_harris:
            score += 25
            subscores["harris_exxon"] = True
            feedback_parts.append("Jessica Harris / ExxonMobil: FOUND")
        else:
            subscores["harris_exxon"] = False
            feedback_parts.append("Jessica Harris / ExxonMobil: NOT FOUND")

        # Criterion 3: Margaret Allen / IBM Corporation (25 points)
        has_allen = "allen" in content_lower or "ibm" in content_lower
        if has_allen:
            score += 25
            subscores["allen_ibm"] = True
            feedback_parts.append("Margaret Allen / IBM Corporation: FOUND")
        else:
            subscores["allen_ibm"] = False
            feedback_parts.append("Margaret Allen / IBM Corporation: NOT FOUND")

        # Criterion 4: Time/duration information present (25 points)
        # Check for sign-in/sign-out times or duration figures
        time_keywords = [
            "10:00", "12:30", "08:30", "11:30",
            "150", "180", "2:30", "3:00", "2.5", "3.0",
            "hour", "min", "duration", "overstay", "elapsed",
        ]
        has_duration = any(kw in content_lower for kw in time_keywords)
        if has_duration:
            score += 25
            subscores["duration_info"] = True
            feedback_parts.append("Duration/time information: FOUND")
        else:
            subscores["duration_info"] = False
            feedback_parts.append("Duration/time information: NOT FOUND in report")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "file_size_bytes": result.get("file_size", 0),
                "content_preview": content[:300] if content else "",
            },
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result JSON not found — export_result.sh may not have run or setup failed",
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
