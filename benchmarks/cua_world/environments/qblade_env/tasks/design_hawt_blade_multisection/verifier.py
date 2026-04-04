#!/usr/bin/env python3
"""Verifier for design_hawt_blade_multisection task.

Scoring (100 points):
- Project file exists at expected path: 25 points
- File is not a copy of any sample project (anti-copy): 20 points
- File is substantial (>5KB, indicating real blade data): 20 points
- New work detected (current_wpa_count > initial): 10 points
- File has significant content (>20KB, multi-station blade): 15 points
- QBlade was running: 10 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_design_hawt_blade_multisection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Project file exists (25 pts)
        try:
            if not result.get('file_exists'):
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "Project file not found at expected path"
                }
            score += 25
            subscores['file_exists'] = True
            feedback_parts.append("Project file exists")
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"File check error: {e}"}

        # Criterion 2: Not a copy of sample project (20 pts)
        try:
            if result.get('file_is_unique'):
                score += 20
                subscores['unique_file'] = True
                feedback_parts.append("File is unique (not a sample copy)")
            else:
                feedback_parts.append("CRITICAL: File appears to be a copy of a sample project")
        except Exception as e:
            feedback_parts.append(f"Uniqueness check error: {e}")

        # Criterion 3: File is substantial >5KB (20 pts)
        try:
            file_size = result.get('file_size', 0)
            if file_size > 5000:
                score += 20
                subscores['substantial'] = True
                feedback_parts.append(f"Substantial file: {file_size} bytes")
            elif file_size > 1000:
                score += 10
                feedback_parts.append(f"Small file: {file_size} bytes (may lack full blade data)")
            elif file_size > 0:
                score += 5
                feedback_parts.append(f"Minimal file: {file_size} bytes")
            else:
                feedback_parts.append("File is empty")
        except Exception as e:
            feedback_parts.append(f"Size check error: {e}")

        # Criterion 4: New work detected (10 pts)
        try:
            initial = result.get('initial_wpa_count', 0)
            current = result.get('current_wpa_count', 0)
            if current > initial:
                score += 10
                subscores['new_work'] = True
                feedback_parts.append(f"New project file created ({initial} -> {current})")
            else:
                feedback_parts.append("No new .wpa files detected (may be overwrite)")
                # Don't penalize if file exists — could be saved to an existing path
                if result.get('file_exists'):
                    score += 5
        except Exception as e:
            feedback_parts.append(f"New work check error: {e}")

        # Criterion 5: Significant content >20KB (multi-station blade) (15 pts)
        try:
            file_size = result.get('file_size', 0)
            if file_size > 20000:
                score += 15
                subscores['complex_content'] = True
                feedback_parts.append(f"Complex project content: {file_size} bytes")
            elif file_size > 10000:
                score += 8
                feedback_parts.append(f"Moderate content: {file_size} bytes")
            elif file_size > 5000:
                score += 4
                feedback_parts.append(f"Basic content: {file_size} bytes")
        except Exception as e:
            feedback_parts.append(f"Content check error: {e}")

        # Criterion 6: QBlade running (10 pts)
        try:
            if result.get('qblade_running'):
                score += 10
                subscores['qblade_running'] = True
                feedback_parts.append("QBlade running")
        except Exception as e:
            feedback_parts.append(f"QBlade check error: {e}")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
