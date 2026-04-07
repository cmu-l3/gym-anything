"""
Verifier for market_brief_synthesis task.

Task: Market Research Analyst must fix a contaminated EV market brief by:
  1. Removing 3 pharmaceutical distribution slides (not EV-related)
  2. Reordering EV slides to match client-mandated narrative sequence

Original deck: 20 slides (3 pharma contamination at positions 6, 13, 18; EV slides scrambled)
Expected corrected deck: 17 slides, first 10 in required order

Scoring (100 pts total):
- 10 pts: Output file /home/ga/Documents/EV_brief_corrected.pptx exists
- 10 pts: Original EV_market_brief.pptx unchanged (still 20 slides)
- 10 pts each × 3 pharma slides removed = 30 pts
- 5 pts each × 10 correctly ordered slides = 50 pts

Pass threshold: 65 pts
"""

import json
import os

RESULT_FILE = '/tmp/market_brief_synthesis_result.json'

REQUIRED_ORDER = [
    "executive summary",
    "us ev market size and growth",
    "ev adoption by segment",
    "key oem market share",
    "battery technology landscape",
    "charging infrastructure build-out",
    "consumer purchase intent drivers",
    "policy environment: ira and state incentives",
    "competitive threat: chinese oems",
    "12-month outlook and risks",
]


def verify_market_brief_synthesis(trajectory, env_info, task_info):
    local_tmp = '/tmp/_market_brief_synthesis_result_local.json'
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

    if result.get('error') and not result.get('output_exists'):
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Export error: {result["error"]}',
        }

    # Anti-gaming check
    try:
        with open('/tmp/market_brief_synthesis_start_ts', 'r') as f:
            task_start = int(f.read().strip())
        output_mtime = result.get('output_mtime', 0)
        if output_mtime and output_mtime <= task_start:
            return {
                'passed': False,
                'score': 0,
                'feedback': 'Output file was not created during this task.',
            }
    except Exception:
        pass

    score = 0
    feedback_parts = []

    # 1. Output file exists (10 pts)
    if result.get('output_exists'):
        score += 10
        n = result.get('output_slide_count', 0)
        feedback_parts.append(f'✓ Output file EV_brief_corrected.pptx exists ({n} slides) (+10 pts)')
    else:
        return {
            'passed': False,
            'score': 0,
            'feedback': '\n'.join([
                'Score: 0/100',
                '✗ Output file not found at /home/ga/Documents/EV_brief_corrected.pptx',
            ]),
        }

    # 2. Original unchanged (10 pts)
    if result.get('original_unchanged'):
        score += 10
        feedback_parts.append(
            f'✓ Original EV_market_brief.pptx unchanged ({result["original_slide_count"]} slides) (+10 pts)'
        )
    else:
        feedback_parts.append(
            f'✗ Original file modified (count={result.get("original_slide_count", "?")}). '
            f'Do not overwrite EV_market_brief.pptx (0 pts).'
        )

    # 3. Pharma slides removed (10 pts each × 3 = 30 pts)
    pharma_remaining = result.get('pharma_slides_remaining', [])
    num_pharma_removed = max(0, 3 - len(pharma_remaining))
    pharma_pts = num_pharma_removed * 10
    score += pharma_pts

    if num_pharma_removed == 3:
        feedback_parts.append(f'✓ All 3 pharmaceutical slides removed (+30 pts)')
    elif num_pharma_removed > 0:
        remaining = [f'slide {r["pos"]}: "{r["title"]}"' for r in pharma_remaining]
        feedback_parts.append(
            f'~ {num_pharma_removed}/3 pharma slides removed (+{pharma_pts} pts). '
            f'Remaining: {"; ".join(remaining)}'
        )
    else:
        remaining = [f'"{r["title"]}"' for r in pharma_remaining]
        feedback_parts.append(
            f'✗ No pharmaceutical slides removed (0 pts). '
            f'Still present: {"; ".join(remaining)}'
        )

    # 4. Slide order (5 pts each × 10 = 50 pts)
    order_score = result.get('first_10_order_score', 0)
    order_pts = order_score * 5
    score += order_pts
    actual_titles = result.get('first_10_actual_titles', [])

    if order_score == 10:
        feedback_parts.append(f'✓ All 10 required slides in correct order (+50 pts)')
    elif order_score > 0:
        mismatches = []
        for i, req in enumerate(REQUIRED_ORDER):
            actual = actual_titles[i].lower().strip() if i < len(actual_titles) else "(missing)"
            if req not in actual and actual not in req:
                mismatches.append(f'slot {i+1}: expected "{req}" got "{actual_titles[i] if i < len(actual_titles) else "(missing)"}"')
        feedback_parts.append(
            f'~ {order_score}/10 slides in correct order (+{order_pts} pts). '
            f'Mismatches: {"; ".join(mismatches[:3])}'
        )
    else:
        feedback_parts.append(
            f'✗ Slides not in required order (0 pts). '
            f'Reorder per ev_brief_spec.txt: Executive Summary first, then Market Size, Adoption, OEM Share, Battery, Charging, Consumer, Policy, Chinese OEMs, Outlook.'
        )

    passed = score >= 65
    output_count = result.get('output_slide_count', 0)

    return {
        'passed': passed,
        'score': score,
        'feedback': '\n'.join([
            f'Score: {score}/100  (pass threshold: 65)',
            f'Output: {output_count} slides',
            f'Pharma slides removed: {num_pharma_removed}/3',
            f'Slide order: {order_score}/10 correct',
            '',
        ] + feedback_parts),
    }
