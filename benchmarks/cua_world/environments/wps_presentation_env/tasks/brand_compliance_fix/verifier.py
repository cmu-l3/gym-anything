"""
Verifier for brand_compliance_fix task.

Scoring (100 pts total):
- 15 pts: branded file exists at /home/ga/Documents/branded_cloudserver.pptx
- 25 pts: first slide title exactly matches "CloudServer Pro: Performance Benchmarking Solutions"
- 15 pts: last slide title is "Contact Us"
- 15 pts: last slide body contains email "sales@cloudserverpro.com"
- 5 pts:  last slide body contains phone "1-800-CLOUD-PRO"
- 5 pts each × 4 ALL CAPS violations fixed = 20 pts
  (injected at slides 5, 9, 14, 20 (1-indexed); each fixed = +5)

Pass threshold: 65 pts
"""

import json
import os

REQUIRED_FIRST_TITLE = "CloudServer Pro: Performance Benchmarking Solutions"
REQUIRED_LAST_TITLE = "Contact Us"
REQUIRED_EMAIL = "sales@cloudserverpro.com"
REQUIRED_PHONE = "1-800-CLOUD-PRO"

# 1-indexed positions of injected ALL CAPS slides
ALL_CAPS_POSITIONS = [5, 9, 14, 20]

RESULT_FILE = '/tmp/brand_compliance_fix_result.json'


def is_all_caps_title(title):
    alpha_chars = [c for c in title if c.isalpha()]
    return len(alpha_chars) > 3 and all(c.isupper() for c in alpha_chars)


def verify_brand_compliance_fix(trajectory, env_info, task_info):
    local_tmp = '/tmp/_brand_compliance_result_local.json'
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

    if result.get('error') and not result.get('branded_exists'):
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Export error: {result["error"]}',
        }

    score = 0
    feedback_parts = []

    branded_exists = result.get('branded_exists', False)
    first_title = result.get('first_slide_title', '')
    last_title = result.get('last_slide_title', '')
    last_body = result.get('last_slide_body', '')
    all_caps_remaining = result.get('all_caps_count', -1)
    slide_titles = result.get('slide_titles', [])
    branded_mtime = result.get('branded_mtime', 0)

    # Anti-gaming: file must be created after task start
    try:
        with open('/tmp/brand_compliance_fix_start_ts', 'r') as f:
            task_start = int(f.read().strip())
        if int(branded_mtime) <= task_start:
            return {
                'passed': False,
                'score': 0,
                'feedback': 'The branded_cloudserver.pptx was not created after task started.',
            }
    except Exception:
        pass

    # 15 pts: file exists
    if branded_exists:
        score += 15
        feedback_parts.append('✓ branded_cloudserver.pptx exists (+15 pts)')
    else:
        feedback_parts.append('✗ branded_cloudserver.pptx does not exist (0 pts)')
        return {
            'passed': False,
            'score': 0,
            'feedback': '\n'.join([f'Score: 0/100', ''] + feedback_parts),
        }

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

    # 15 pts: last slide title = "Contact Us"
    if last_title.strip() == REQUIRED_LAST_TITLE:
        score += 15
        feedback_parts.append(f'✓ Last slide title is "Contact Us" (+15 pts)')
    elif REQUIRED_LAST_TITLE.lower() in last_title.lower():
        score += 7
        feedback_parts.append(
            f'~ Last slide title partially matches: "{last_title}" (+7 pts). '
            f'Expected exact: "{REQUIRED_LAST_TITLE}"'
        )
    else:
        feedback_parts.append(f'✗ Last slide title is "{last_title}" (expected "Contact Us")')

    # 15 pts: last slide body contains email
    if REQUIRED_EMAIL.lower() in last_body.lower():
        score += 15
        feedback_parts.append(f'✓ Last slide contains email {REQUIRED_EMAIL} (+15 pts)')
    else:
        feedback_parts.append(
            f'✗ Last slide does not contain email "{REQUIRED_EMAIL}". '
            f'Body text: "{last_body[:100]}"'
        )

    # 5 pts: last slide body contains phone
    if REQUIRED_PHONE.lower() in last_body.lower():
        score += 5
        feedback_parts.append(f'✓ Last slide contains phone {REQUIRED_PHONE} (+5 pts)')
    else:
        feedback_parts.append(f'✗ Last slide does not contain phone "{REQUIRED_PHONE}"')

    # 5 pts each for fixing the 4 injected ALL CAPS titles
    for pos in ALL_CAPS_POSITIONS:
        idx = pos - 1  # 0-indexed
        if idx < len(slide_titles):
            title = slide_titles[idx]
            if not is_all_caps_title(title):
                score += 5
                feedback_parts.append(f'✓ Slide {pos} ALL CAPS fixed: "{title[:60]}" (+5 pts)')
            else:
                feedback_parts.append(f'✗ Slide {pos} still ALL CAPS: "{title[:60]}"')
        else:
            feedback_parts.append(f'~ Slide {pos} index out of range (slide count={len(slide_titles)})')

    passed = score >= 65

    return {
        'passed': passed,
        'score': score,
        'feedback': '\n'.join([
            f'Score: {score}/100',
            f'First title: "{first_title}"',
            f'Last title: "{last_title}"',
            f'ALL CAPS remaining: {all_caps_remaining}',
            '',
        ] + feedback_parts),
    }
