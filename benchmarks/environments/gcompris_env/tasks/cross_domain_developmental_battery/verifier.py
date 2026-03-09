#!/usr/bin/env python3
"""
Verifier for cross_domain_developmental_battery task.

A child development psychologist must complete activities from four distinct
cognitive domains in GCompris (Math, Language, Science, Games) and produce a
multi-domain developmental assessment battery report.

Scoring (100 points):
- Report file exists: 10
- Report created after task start (gate): 10
- Report is >=500 bytes: 10
- Math domain documented: 20
- Language domain documented: 20
- Science domain documented: 20
- Games domain documented: 10

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_cross_domain_developmental_battery(traj, env_info, task_info):
    """Verify the cross-domain developmental battery task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/cross_domain_developmental_battery_result.json', tmp.name)
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
            "feedback": "Report file ~/Desktop/developmental_assessment_battery.txt was not created"
        }
    score += 10
    parts.append("Report file created (10/10)")

    # 2. GATE: Report must be created after task started (10 pts)
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
    if size >= 500:
        score += 10
        parts.append(f"Report has substantial content ({size} bytes, 10/10)")
    elif size >= 200:
        score += 5
        parts.append(f"Report is brief ({size} bytes, 5/10)")
    else:
        parts.append(f"Report too short ({size} bytes, 0/10)")

    # 4. Math domain documented (20 pts)
    if result.get('has_math_domain'):
        score += 20
        parts.append("Math/Numerical domain documented (20/20)")
    else:
        parts.append("Missing math domain coverage (0/20)")

    # 5. Language domain documented (20 pts)
    if result.get('has_language_domain'):
        score += 20
        parts.append("Language/Literacy domain documented (20/20)")
    else:
        parts.append("Missing language domain coverage (0/20)")

    # 6. Science domain documented (20 pts)
    if result.get('has_science_domain'):
        score += 20
        parts.append("Science/Inquiry domain documented (20/20)")
    else:
        parts.append("Missing science domain coverage (0/20)")

    # 7. Games/Spatial domain documented (10 pts)
    if result.get('has_games_domain'):
        score += 10
        parts.append("Games/Spatial domain documented (10/10)")
    else:
        parts.append("Missing games/spatial domain coverage (0/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts)
    }
