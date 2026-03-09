#!/usr/bin/env python3
"""
Verifier for reading_readiness_assessment task.

A literacy specialist must navigate all three Language sub-tabs in GCompris
(Letters, Words, Vocabulary), interact with at least 4 activities, and write
a formal reading readiness assessment report.

Scoring (100 points):
- Report file exists: 10
- Report created after task start (gate): 15
- Report is >=400 bytes: 10
- Letters section present: 20
- Words section present: 20
- Vocabulary section present: 10
- 3+ language activity keywords: 15

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_reading_readiness_assessment(traj, env_info, task_info):
    """Verify the reading readiness assessment task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/reading_readiness_assessment_result.json', tmp.name)
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
            "feedback": "Report file ~/Desktop/reading_readiness_report.txt was not created"
        }
    score += 10
    parts.append("Report file created (10/10)")

    # 2. GATE: Report must be created after task started (15 pts)
    if not result.get('report_modified_after_start'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file predates task start — no new work done (timestamp gate failed)"
        }
    score += 15
    parts.append("Report created after task start (15/15)")

    # 3. Report size (10 pts)
    size = result.get('report_size', 0)
    if size >= 400:
        score += 10
        parts.append(f"Report has substantial content ({size} bytes, 10/10)")
    elif size >= 150:
        score += 5
        parts.append(f"Report is brief ({size} bytes, 5/10)")
    else:
        parts.append(f"Report too short ({size} bytes, 0/10)")

    # 4. Letters section (20 pts)
    if result.get('has_letters_section'):
        score += 20
        parts.append("Letters sub-tab section documented (20/20)")
    else:
        parts.append("Missing Letters section (0/20)")

    # 5. Words section (20 pts)
    if result.get('has_words_section'):
        score += 20
        parts.append("Words sub-tab section documented (20/20)")
    else:
        parts.append("Missing Words section (0/20)")

    # 6. Vocabulary section (10 pts)
    if result.get('has_vocabulary_section'):
        score += 10
        parts.append("Vocabulary sub-tab section documented (10/10)")
    else:
        parts.append("Missing Vocabulary section (0/10)")

    # 7. Specific language activity keywords (15 pts)
    lang_keywords = [
        ('has_alphabet_keyword', 'alphabet'),
        ('has_keyboard_keyword', 'keyboard'),
        ('has_uppercase_keyword', 'uppercase'),
        ('has_lowercase_keyword', 'lowercase'),
        ('has_word_processor_keyword', 'word processor'),
        ('has_typing_keyword', 'typing'),
    ]
    kw_count = sum(1 for k, _ in lang_keywords if result.get(k))

    if kw_count >= 3:
        score += 15
        parts.append(f"Activity names well-documented ({kw_count}/6 keywords, 15/15)")
    elif kw_count == 2:
        score += 8
        parts.append(f"Some activity names mentioned ({kw_count}/6 keywords, 8/15)")
    elif kw_count == 1:
        score += 3
        parts.append(f"Minimal activity documentation ({kw_count}/6 keywords, 3/15)")
    else:
        parts.append("No specific language activity names found (0/15)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts)
    }
