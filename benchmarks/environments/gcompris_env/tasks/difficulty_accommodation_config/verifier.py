#!/usr/bin/env python3
"""
Verifier for difficulty_accommodation_config task.

A special education teacher must access GCompris settings, change the difficulty
filter maximum from 6 to ≤3, navigate activity categories with the filter applied,
run accessible activities, and produce an Individual Accommodation Plan document.

Scoring (100 points):
- Report file exists: 10
- Report created after task start (gate): 10
- Report is >=350 bytes: 10
- Report mentions difficulty/level settings: 15
- Report lists Math activities: 20
- Report lists Language activities: 15
- GCompris config filterLevelMax changed from 6: 20

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_difficulty_accommodation_config(traj, env_info, task_info):
    """Verify the difficulty accommodation configuration task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/difficulty_accommodation_config_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # 1. Report exists (10 pts)
    if not result.get('report_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file ~/Desktop/accommodation_plan.txt was not created"
        }
    score += 10
    parts.append("Report file created (10/10)")

    # 2. GATE: Report created after task started (10 pts)
    if not result.get('report_modified_after_start'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file predates task start — no new work done (timestamp gate failed)"
        }
    score += 10
    parts.append("Report created after task start (10/10)")

    # 3. Report size (10 pts)
    size = result.get('report_size', 0)
    if size >= 350:
        score += 10
        parts.append(f"Report has substantial content ({size} bytes, 10/10)")
    elif size >= 120:
        score += 5
        parts.append(f"Report is brief ({size} bytes, 5/10)")
    else:
        parts.append(f"Report too short ({size} bytes, 0/10)")

    # 4. Report mentions difficulty/level settings (15 pts)
    if result.get('has_difficulty_keyword') or result.get('has_level_keyword'):
        score += 15
        parts.append("Difficulty settings documented in report (15/15)")
    else:
        parts.append("Report does not mention difficulty or level settings (0/15)")

    # 5. Report lists Math activities (20 pts)
    if result.get('has_math_list'):
        score += 20
        parts.append("Math activities listed in accommodation plan (20/20)")
    else:
        parts.append("No Math activities listed in report (0/20)")

    # 6. Report lists Language activities (15 pts)
    if result.get('has_language_list'):
        score += 15
        parts.append("Language activities listed in accommodation plan (15/15)")
    else:
        parts.append("No Language activities listed in report (0/15)")

    # 7. GCompris config filterLevelMax was changed (20 pts)
    config_max = result.get('config_filter_max', 6)
    if result.get('config_max_at_target'):
        score += 20
        parts.append(f"GCompris config changed: filterLevelMax={config_max} (≤3, target met, 20/20)")
    elif result.get('config_max_reduced'):
        score += 10
        parts.append(f"GCompris config partially changed: filterLevelMax={config_max} (reduced from 6 but >3, 10/20)")
    else:
        parts.append(f"GCompris config NOT changed: filterLevelMax={config_max} (still at default 6, 0/20)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts)
    }
