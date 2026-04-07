"""
Verifier for clinical_module_fix task.

Task: A medical school ACLS lecture deck has been contaminated with 3 PALS
(pediatric) slides. The course director must identify and remove them, saving
a corrected adult-only deck.

Original deck: 22 slides, 3 contaminating PALS slides at positions 5, 12, 19
Expected corrected deck: 19 slides (3 fewer), no PALS/Pediatric content

Scoring (100 pts total):
- 10 pts: Output file /home/ga/Documents/ACLS_corrected.pptx exists
- 10 pts: Original ACLS_lecture.pptx unchanged (still 22 slides)
- 20 pts each × 3 PALS slides removed = 60 pts (no PALS keyword slides remain)
- 20 pts: Output slide count is 18-20 (approximately correct)

Pass threshold: 65 pts
"""

import json
import os

RESULT_FILE = '/tmp/clinical_module_fix_result.json'
PALS_KEYWORDS = ["pals", "pediatric", "weight-based", "broselow", "0.01 mg/kg", "2 j/kg", "5 mg/kg"]


def verify_clinical_module_fix(trajectory, env_info, task_info):
    local_tmp = '/tmp/_clinical_module_fix_result_local.json'
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

    # Anti-gaming: output must be created after task start
    try:
        with open('/tmp/clinical_module_fix_start_ts', 'r') as f:
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
        feedback_parts.append(f'✓ Output file ACLS_corrected.pptx exists ({n} slides) (+10 pts)')
    else:
        return {
            'passed': False,
            'score': 0,
            'feedback': '\n'.join([
                'Score: 0/100',
                '✗ Output file not found at /home/ga/Documents/ACLS_corrected.pptx',
                'Save the corrected presentation to this exact path.',
            ]),
        }

    # 2. Original unchanged (10 pts)
    if result.get('original_unchanged'):
        score += 10
        feedback_parts.append(
            f'✓ Original ACLS_lecture.pptx still has {result["original_slide_count"]} slides (+10 pts)'
        )
    else:
        feedback_parts.append(
            f'✗ Original file modified or not found (count={result.get("original_slide_count", "?")}). '
            f'Never overwrite ACLS_lecture.pptx (0 pts).'
        )

    # 3. PALS slides removed (20 pts each × 3 = 60 pts)
    # Anti-Pattern 11 guard: an empty PPTX trivially has no PALS slides.
    # Require at least 15 slides to prove a real corrected deck was saved (not blanked out).
    pals_remaining = result.get('pals_slides_remaining', [])
    output_count = result.get('output_slide_count', 0)
    if output_count < 15:
        num_pals_removed = 0
        pals_pts = 0
        feedback_parts.append(
            f'✗ Output deck has only {output_count} slides — too few to be a valid corrected ACLS deck. '
            f'Do not delete non-PALS slides. Expected ~19 slides. (0 pts for PALS removal)'
        )
    else:
        # The original had 3 PALS slides; count removed
        num_pals_removed = max(0, 3 - len(pals_remaining))
        pals_pts = num_pals_removed * 20
        score += pals_pts

    if num_pals_removed == 3:
        feedback_parts.append(f'✓ All 3 PALS/pediatric slides successfully removed (+60 pts)')
    elif num_pals_removed > 0:
        remaining_info = [f'slide {r["pos"]}: "{r["title"]}" [{r["matched_keywords"]}]'
                          for r in pals_remaining]
        feedback_parts.append(
            f'~ {num_pals_removed}/3 PALS slides removed (+{pals_pts} pts). '
            f'Still contains pediatric content: {"; ".join(remaining_info)}'
        )
    else:
        remaining_info = [f'slide {r["pos"]}: "{r["title"]}"' for r in pals_remaining]
        feedback_parts.append(
            f'✗ No PALS slides removed (0/3, +0 pts). '
            f'Find slides with PALS/pediatric keywords and delete them: {"; ".join(remaining_info)}'
        )

    # 4. Correct slide count (20 pts)
    # output_count already set above
    if 18 <= output_count <= 20:
        score += 20
        feedback_parts.append(
            f'✓ Output deck has {output_count} slides (expected ~19 after removing 3) (+20 pts)'
        )
    elif output_count > 0:
        feedback_parts.append(
            f'~ Output deck has {output_count} slides (expected 18–20 after removing 3 PALS slides). '
            f'Check that you removed exactly the PALS slides. (+0 pts for count)'
        )

    passed = score >= 65

    return {
        'passed': passed,
        'score': score,
        'feedback': '\n'.join([
            f'Score: {score}/100  (pass threshold: 65)',
            f'Output file: {output_count} slides',
            f'PALS slides removed: {num_pals_removed}/3',
            '',
        ] + feedback_parts),
    }
