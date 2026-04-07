"""
Verifier for investor_pitch_audit task.

Task: Financial Controller at Meridian Technology Group must correct a 30-slide
investor presentation before the earnings call by:
  1. Fixing all "Q2 2024" titles to "Q3 2024" (4 slides)
  2. Removing the contaminating competitor slide (Apex Digital Solutions)
  3. Adding a Forward-Looking Statements disclaimer as slide 2

Scoring (100 pts total):
- 10 pts: Output file /home/ga/Documents/Q3_board_corrected.pptx exists
- 10 pts: Original file at /home/ga/Documents/financial_report.pptx still has 30 slides (unchanged)
- 5 pts each × 4 quarter fixes = 20 pts (no "Q2 2024" remaining in slide titles)
- 20 pts: Competitor slide removed (no "Apex Digital" in any title or first 100 chars of body)
- 20 pts: Forward-Looking Statements slide exists somewhere in the deck
- 20 pts: FLS slide is at position 2 and body contains key required phrases

Pass threshold: 65 pts
"""

import json
import os

RESULT_FILE = '/tmp/investor_pitch_audit_result.json'
FLS_KEY_PHRASES = [
    "forward-looking statements",
    "risks and uncertainties",
    "section 27a",
    "section 21e",
]


def verify_investor_pitch_audit(trajectory, env_info, task_info):
    local_tmp = '/tmp/_investor_pitch_audit_result_local.json'
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

    score = 0
    feedback_parts = []

    # Anti-gaming: output must be created after task start
    try:
        with open('/tmp/investor_pitch_audit_start_ts', 'r') as f:
            task_start = int(f.read().strip())
        output_mtime = result.get('output_mtime', 0)
        if output_mtime and output_mtime <= task_start:
            return {
                'passed': False,
                'score': 0,
                'feedback': 'Output file existed before the task started. File was not created during this task.',
            }
    except Exception:
        pass

    # 1. Output file exists (10 pts)
    if result.get('output_exists'):
        score += 10
        n = result.get('output_slide_count', 0)
        feedback_parts.append(f'✓ Output file Q3_board_corrected.pptx exists ({n} slides) (+10 pts)')
    else:
        feedback_parts.append(
            '✗ Output file not found at /home/ga/Documents/Q3_board_corrected.pptx (0 pts). '
            'Save the corrected presentation to this exact path.'
        )
        return {
            'passed': False,
            'score': 0,
            'feedback': '\n'.join(['Score: 0/100', ''] + feedback_parts),
        }

    # 2. Original file unchanged (10 pts)
    if result.get('original_unchanged'):
        score += 10
        feedback_parts.append(
            f'✓ Original financial_report.pptx still has {result["original_slide_count"]} slides (+10 pts)'
        )
    else:
        orig_count = result.get('original_slide_count', '?')
        feedback_parts.append(
            f'✗ Original file was modified or not found (slide count: {orig_count}, expected 30). '
            f'Never overwrite financial_report.pptx. (0 pts for this criterion)'
        )

    # 3. Quarter references fixed (5 pts each, 4 slides = 20 pts)
    q2_remaining = result.get('q2_slides_remaining', [])
    # Original had 4 errors; count fixed
    num_fixed = max(0, 4 - len(q2_remaining))
    quarter_pts = num_fixed * 5
    score += quarter_pts
    if num_fixed == 4:
        feedback_parts.append(f'✓ All 4 "Q2 2024" title errors corrected to "Q3 2024" (+20 pts)')
    elif num_fixed > 0:
        remaining_titles = [f'slide {r["pos"]}: "{r["title"]}"' for r in q2_remaining]
        feedback_parts.append(
            f'~ {num_fixed}/4 quarter errors fixed (+{quarter_pts} pts). '
            f'Still contains "Q2 2024": {", ".join(remaining_titles)}'
        )
    else:
        remaining_titles = [f'slide {r["pos"]}: "{r["title"]}"' for r in q2_remaining]
        feedback_parts.append(
            f'✗ No quarter errors fixed (0/4). Still contains "Q2 2024" slides: '
            f'{", ".join(remaining_titles)}. Search for "Q2 2024" in slide titles and correct to "Q3 2024".'
        )

    # 4. Competitor slide removed (20 pts)
    competitor_remaining = result.get('competitor_slide_titles', [])
    if not competitor_remaining:
        score += 20
        feedback_parts.append('✓ Competitor slide (Apex Digital Solutions) removed (+20 pts)')
    else:
        titles = [f'slide {c["pos"]}: "{c["title"]}"' for c in competitor_remaining]
        feedback_parts.append(
            f'✗ Competitor slide still present: {", ".join(titles)} (0 pts). '
            f'Delete any slide referencing "Apex Digital Solutions" or "APXD".'
        )

    # 5. Forward-Looking Statements disclaimer exists (20 pts)
    fls_pos = result.get('fls_slide_position')
    fls_body = result.get('fls_body_text', '').lower()
    fls_title = result.get('fls_slide_title', '')

    if fls_pos is not None:
        score += 20
        feedback_parts.append(
            f'✓ Forward-Looking Statements slide found at position {fls_pos} (+20 pts)'
        )

        # 6. FLS at position 2 and body has required phrases (20 pts)
        phrases_found = [p for p in FLS_KEY_PHRASES if p in fls_body]
        at_position_2 = (fls_pos == 2)
        phrase_score = len(phrases_found) * 4  # 4 pts each, max 16 pts
        position_score = 4 if at_position_2 else 0
        fls_quality_score = min(20, phrase_score + position_score)
        score += fls_quality_score

        if at_position_2:
            feedback_parts.append(f'✓ FLS disclaimer correctly placed at slide 2 (+4 pts)')
        else:
            feedback_parts.append(
                f'~ FLS slide is at position {fls_pos}, not position 2 as required. '
                f'Move it immediately after the title slide. (+0 pts for position)'
            )

        if phrases_found:
            feedback_parts.append(
                f'✓ FLS body contains {len(phrases_found)}/{len(FLS_KEY_PHRASES)} required phrases '
                f'(+{phrase_score} pts): {phrases_found}'
            )
        else:
            feedback_parts.append(
                f'✗ FLS body does not contain required phrases. '
                f'Copy exact text from meridian_compliance.txt (0 pts for content).'
            )
    else:
        feedback_parts.append(
            '✗ No "Forward-Looking Statements" slide found in the corrected deck (0 pts). '
            'Add a new slide titled "Forward-Looking Statements" as slide 2 with the '
            'disclaimer text from meridian_compliance.txt.'
        )

    passed = score >= 65

    slide_count = result.get('output_slide_count', 0)
    return {
        'passed': passed,
        'score': score,
        'feedback': '\n'.join([
            f'Score: {score}/100  (pass threshold: 65)',
            f'Output file: {slide_count} slides',
            f'Q2 errors fixed: {num_fixed}/4',
            f'Competitor slide removed: {"yes" if not competitor_remaining else "no"}',
            f'FLS disclaimer: {"found at slide " + str(fls_pos) if fls_pos else "missing"}',
            '',
        ] + feedback_parts),
    }
