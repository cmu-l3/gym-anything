#!/usr/bin/env python3
"""
Verifier for defense_sector_host_compliance task.

Scoring (100 points total):
- Prerequisite: File /home/ga/Desktop/defense_host_compliance.csv exists (else score=0)
- Criterion 1: Boeing Company with non-Security host (Compliance dept) — 25 pts
- Criterion 2: Lockheed Martin with non-Security host (Legal dept) — 25 pts
- Criterion 3: Northrop Grumman with non-Security host (Procurement dept) — 25 pts
- Criterion 4: Non-Security host departments referenced — 25 pts

Passing threshold: 70 points (3 of 4 scored criteria)

Ground truth — defense/aerospace visitors with non-Security hosts:
  1. William Wilson  / Boeing Company  → Compliance (Karen Clark)   [VIOLATION]
  2. Charles White   / Lockheed Martin → Legal (Michelle Allen)      [VIOLATION]
  3. Andrew Adams    / Northrop Grumman → Procurement (Maria Edwards) [VIOLATION]
  4. Joshua Scott    / Raytheon        → Security (Cynthia Parker)   [COMPLIANT — not a violation]
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_defense_sector_host_compliance(traj, env_info, task_info):
    """Verify the defense sector host compliance gap report."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        # Step 1: Copy the exported result JSON
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env(
                "/tmp/defense_sector_host_compliance_result.json", temp_json.name
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
                "feedback": "Output file /home/ga/Desktop/defense_host_compliance.csv not found. Agent did not create the compliance gap report.",
            }

        # Step 2: Independently copy the actual output file
        content = result.get("file_content", "")
        try:
            temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
            copy_from_env(
                "/home/ga/Desktop/defense_host_compliance.csv", temp_csv.name
            )
            with open(temp_csv.name, "r", encoding="utf-8", errors="replace") as f:
                content = f.read(6000)
            os.unlink(temp_csv.name)
            logger.info("Used independently-copied file for verification")
        except Exception as e:
            logger.warning(f"Independent file copy failed, using JSON content: {e}")

        content_lower = content.lower()

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Boeing Company with non-Security host (25 points)
        # Host is Karen Clark in Compliance department
        has_boeing = "boeing" in content_lower
        if has_boeing:
            score += 25
            subscores["boeing_violation"] = True
            feedback_parts.append("Boeing Company compliance violation: FOUND")
        else:
            subscores["boeing_violation"] = False
            feedback_parts.append("Boeing Company: NOT FOUND (expected as a violation)")

        # Criterion 2: Lockheed Martin with non-Security host (25 points)
        # Host is Michelle Allen in Legal department
        has_lockheed = "lockheed" in content_lower or "lmco" in content_lower
        if has_lockheed:
            score += 25
            subscores["lockheed_violation"] = True
            feedback_parts.append("Lockheed Martin compliance violation: FOUND")
        else:
            subscores["lockheed_violation"] = False
            feedback_parts.append("Lockheed Martin: NOT FOUND (expected as a violation)")

        # Criterion 3: Northrop Grumman with non-Security host (25 points)
        # Host is Maria Edwards in Procurement department
        has_northrop = "northrop" in content_lower or "grumman" in content_lower
        if has_northrop:
            score += 25
            subscores["northrop_violation"] = True
            feedback_parts.append("Northrop Grumman compliance violation: FOUND")
        else:
            subscores["northrop_violation"] = False
            feedback_parts.append("Northrop Grumman: NOT FOUND (expected as a violation)")

        # Criterion 4: Non-Security host departments referenced (25 points)
        # The violations involve: Compliance, Legal, Procurement
        non_security_depts = ["compliance", "legal", "procurement"]
        depts_found = [d for d in non_security_depts if d in content_lower]
        if len(depts_found) >= 2:
            score += 25
            subscores["non_security_depts"] = True
            feedback_parts.append(f"Non-Security host departments referenced: {depts_found}")
        elif len(depts_found) == 1:
            score += 12
            subscores["non_security_depts"] = False
            feedback_parts.append(f"Only 1 non-Security department found: {depts_found}")
        else:
            subscores["non_security_depts"] = False
            feedback_parts.append("No non-Security host departments (Compliance/Legal/Procurement) found in report")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "file_size_bytes": result.get("file_size", 0),
                "content_preview": content[:300] if content else "",
                "depts_found": depts_found,
            },
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result JSON not found — export_result.sh may not have run",
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
