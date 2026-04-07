"""
Verifier for executive_briefing_from_spec task.

Scoring (100 pts total):
- 15 pts: briefing file exists at /home/ga/Documents/executive_briefing.pptx
- 20 pts: slide count <= 12
- 25 pts: first slide title exactly matches "Apache Infrastructure: Q4 2024 Executive Briefing"
- 15 pts: last slide contains "Q&A" or "Questions"
- 15 pts: non-default theme applied (slide count evidence, or theme name differs from default)
- 10 pts: file is different from original (agent actually created a new condensed version)

Pass threshold: 65 pts
"""

import json
import os


REQUIRED_FIRST_TITLE = "Apache Infrastructure: Q4 2024 Executive Briefing"
RESULT_FILE = '/tmp/executive_briefing_from_spec_result.json'


def verify_executive_briefing_from_spec(trajectory, env_info, task_info):
    local_tmp = '/tmp/_executive_briefing_result_local.json'
    try:
        env_info['copy_from_env'](RESULT_FILE, local_tmp)
    except Exception as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Could not retrieve result file: {e}. Export script may not have run.',
        }

    try:
        with open(local_tmp, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Could not parse result JSON: {e}',
        }

    if result.get('error') and not result.get('briefing_exists'):
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Export error: {result["error"]}',
        }

    score = 0
    feedback_parts = []

    briefing_exists = result.get('briefing_exists', False)
    slide_count = result.get('slide_count', 0)
    first_title = result.get('first_slide_title', '')
    last_title = result.get('last_slide_title', '')
    last_body = result.get('last_slide_body', '')
    theme_name = result.get('theme_name', '')
    orig_slide_count = result.get('original_slide_count', 48)

    # Check anti-gaming: file must be created after task start
    try:
        with open('/tmp/executive_briefing_from_spec_start_ts', 'r') as f:
            task_start = int(f.read().strip())
        briefing_mtime = result.get('briefing_mtime', 0)
        if int(briefing_mtime) <= task_start:
            return {
                'passed': False,
                'score': 0,
                'feedback': 'The executive_briefing.pptx file was not created after the task started. Please create the file during the task.',
            }
    except Exception:
        pass

    # 15 pts: file exists
    if briefing_exists:
        score += 15
        feedback_parts.append(f'✓ executive_briefing.pptx exists (+15 pts)')
    else:
        feedback_parts.append(f'✗ executive_briefing.pptx does not exist (0 pts)')
        return {
            'passed': False,
            'score': score,
            'feedback': '\n'.join([f'Score: {score}/100', ''] + feedback_parts),
        }

    # 20 pts: slide count <= 12
    if slide_count <= 12 and slide_count >= 1:
        score += 20
        feedback_parts.append(f'✓ Slide count {slide_count} <= 12 (+20 pts)')
    elif slide_count > 12:
        feedback_parts.append(f'✗ Too many slides: {slide_count} (must be ≤ 12) (0 pts)')
    else:
        feedback_parts.append(f'✗ Slide count is {slide_count} — empty presentation (0 pts)')

    # 25 pts: exact first slide title
    if first_title.strip() == REQUIRED_FIRST_TITLE:
        score += 25
        feedback_parts.append(f'✓ First slide title exact match (+25 pts)')
    else:
        feedback_parts.append(
            f'✗ First slide title mismatch.\n'
            f'  Expected: "{REQUIRED_FIRST_TITLE}"\n'
            f'  Got:      "{first_title}"'
        )

    # 15 pts: last slide contains Q&A or Questions
    last_combined = (last_title + ' ' + last_body).lower()
    if 'q&a' in last_combined or 'questions' in last_combined:
        score += 15
        feedback_parts.append(f'✓ Last slide contains Q&A/Questions (+15 pts)')
    else:
        feedback_parts.append(
            f'✗ Last slide does not contain "Q&A" or "Questions".\n'
            f'  Last slide title: "{last_title}"'
        )

    # 15 pts: non-default theme (theme name present OR slide count significantly different from original)
    # WPS default theme names are usually empty or "Office Theme"
    has_theme = (
        theme_name and
        theme_name.lower() not in ('', 'office theme', 'default theme', 'blank', 'normal')
    )
    if has_theme:
        score += 15
        feedback_parts.append(f'✓ Non-default theme detected: "{theme_name}" (+15 pts)')
    else:
        # Give partial credit if we can't determine theme but file is non-trivial
        score += 5
        feedback_parts.append(
            f'~ Theme could not be verified (theme name: "{theme_name}"). '
            f'Partial credit: +5 pts. Apply a named design theme in WPS Design tab for full credit.'
        )

    # 10 pts: file has fewer slides than original (agent condensed it)
    if orig_slide_count > 0 and slide_count < orig_slide_count and slide_count >= 1:
        score += 10
        feedback_parts.append(
            f'✓ Briefing ({slide_count} slides) is condensed from original ({orig_slide_count} slides) (+10 pts)'
        )
    elif slide_count >= orig_slide_count and orig_slide_count > 0:
        feedback_parts.append(
            f'✗ Briefing has {slide_count} slides — same or more than original ({orig_slide_count}). '
            f'Must condense to ≤12 slides.'
        )

    passed = score >= 65

    return {
        'passed': passed,
        'score': score,
        'feedback': '\n'.join([
            f'Score: {score}/100',
            f'Slide count: {slide_count}',
            f'First title: "{first_title}"',
            f'Last title: "{last_title}"',
            '',
        ] + feedback_parts),
    }
