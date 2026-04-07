"""
Verifier for esg_compliance_fix task.

Task: Head of Sustainability must fix an ESG Disclosure Report presentation:
  1. Correct 3 wrong GRI Standard codes in slide titles
  2. Reorder 4 TCFD pillar slides into correct sequence (Governance → Strategy → Risk → Metrics)
  3. Remove 2 marketing/promotional slides that don't belong in an ESG disclosure

Original deck: 24 slides; corrected deck should have 22 slides (2 removed)

Scoring (100 pts total):
- 10 pts: Output file /home/ga/Documents/ESG_corrected.pptx exists
- 10 pts: Original ESG_board_presentation.pptx unchanged (24 slides)
- 10 pts each × 3 GRI code corrections = 30 pts
- 20 pts: TCFD pillars in correct order (Governance→Strategy→Risk Mgmt→Metrics)
- 10 pts each × 2 marketing slides removed = 20 pts
- 10 pts: Output deck has 21-23 slides (approximately correct after removals)

Pass threshold: 65 pts
"""

import json
import os

RESULT_FILE = '/tmp/esg_compliance_fix_result.json'

TCFD_REQUIRED_SEQUENCE = [
    "tcfd pillar 1: governance",
    "tcfd pillar 2: strategy",
    "tcfd pillar 3: risk management",
    "tcfd pillar 4: metrics and targets",
]

WRONG_GRI_PAIRS = [
    ("emissions disclosure", "302-1", "305-1"),
    ("energy consumption data", "305-2", "302"),
    ("water withdrawal data", "401-3", "303-3"),
]


def verify_esg_compliance_fix(trajectory, env_info, task_info):
    local_tmp = '/tmp/_esg_compliance_fix_result_local.json'
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
        with open('/tmp/esg_compliance_fix_start_ts', 'r') as f:
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
        feedback_parts.append(f'✓ Output file ESG_corrected.pptx exists ({n} slides) (+10 pts)')
    else:
        return {
            'passed': False,
            'score': 0,
            'feedback': '\n'.join([
                'Score: 0/100',
                '✗ Output file not found at /home/ga/Documents/ESG_corrected.pptx',
            ]),
        }

    # 2. Original unchanged (10 pts)
    if result.get('original_unchanged'):
        score += 10
        feedback_parts.append(
            f'✓ Original ESG_board_presentation.pptx unchanged '
            f'({result["original_slide_count"]} slides) (+10 pts)'
        )
    else:
        feedback_parts.append(
            f'✗ Original file modified (count={result.get("original_slide_count", "?")}). '
            f'Do not overwrite ESG_board_presentation.pptx (0 pts).'
        )

    # Anti-Pattern 11 guard: an empty PPTX trivially has no wrong GRI codes or marketing slides.
    # Gate absence-based criteria on a minimum viable slide count.
    output_count = result.get('output_slide_count', 0)
    if output_count < 15:
        feedback_parts.append(
            f'✗ Output deck has only {output_count} slides — far too few for a valid ESG report. '
            f'Do not mass-delete slides. Expected ~22 slides after removing 2 marketing slides. '
            f'GRI, TCFD, and marketing criteria cannot be scored. (0 pts for these criteria)'
        )
        passed = score >= 65
        return {
            'passed': False,
            'score': score,
            'feedback': '\n'.join([f'Score: {score}/100  (pass threshold: 65)', ''] + feedback_parts),
        }

    # 3. GRI code corrections (10 pts each × 3 = 30 pts)
    gri_still_wrong = result.get('gri_still_wrong', [])
    num_gri_fixed = max(0, 3 - len(gri_still_wrong))
    gri_pts = num_gri_fixed * 10
    score += gri_pts

    if num_gri_fixed == 3:
        feedback_parts.append(f'✓ All 3 GRI Standard code errors corrected (+30 pts)')
    elif num_gri_fixed > 0:
        still_wrong = [f'"{r["title"]}" ({r["problem"]})' for r in gri_still_wrong]
        feedback_parts.append(
            f'~ {num_gri_fixed}/3 GRI codes fixed (+{gri_pts} pts). '
            f'Still incorrect: {"; ".join(still_wrong)}'
        )
    else:
        still_wrong = [f'"{r["title"]}"' for r in gri_still_wrong]
        feedback_parts.append(
            f'✗ No GRI code errors fixed (0 pts). '
            f'Check slide titles against the code reference in esg_auditor_memo.txt. '
            f'Problematic titles: {"; ".join(still_wrong)}'
        )

    # 4. TCFD order (20 pts)
    tcfd_order = result.get('tcfd_order', [])
    positions = [x.get('pos') for x in tcfd_order if x.get('pos') is not None]
    tcfd_correct = result.get('tcfd_order_correct', False)

    if len(positions) == 4 and tcfd_correct:
        score += 20
        feedback_parts.append(f'✓ TCFD pillars in correct order (Governance→Strategy→Risk Mgmt→Metrics) (+20 pts)')
    elif len(positions) == 4:
        pos_info = ', '.join([f'{x["pillar"].split(": ")[-1]} @ slide {x["pos"]}' for x in tcfd_order])
        feedback_parts.append(
            f'✗ TCFD pillars present but in wrong order: {pos_info}. '
            f'Required order: Governance → Strategy → Risk Management → Metrics and Targets (0 pts).'
        )
    elif len(positions) > 0:
        feedback_parts.append(
            f'~ Only {len(positions)}/4 TCFD pillar slides found in output deck. '
            f'Do not delete TCFD slides — reorder them. (0 pts)'
        )
    else:
        feedback_parts.append(
            '✗ No TCFD pillar slides found in output deck. '
            'Reorder the 4 TCFD slides — do not delete them. (0 pts)'
        )

    # 5. Marketing slides removed (10 pts each × 2 = 20 pts)
    marketing_remaining = result.get('marketing_slides_remaining', [])
    num_mkt_removed = max(0, 2 - len(marketing_remaining))
    mkt_pts = num_mkt_removed * 10
    score += mkt_pts

    if num_mkt_removed == 2:
        feedback_parts.append(f'✓ Both marketing/promotional slides removed (+20 pts)')
    elif num_mkt_removed == 1:
        remaining = [f'"{r["title"]}"' for r in marketing_remaining]
        feedback_parts.append(
            f'~ 1/2 marketing slides removed (+10 pts). '
            f'Still present: {"; ".join(remaining)}'
        )
    else:
        remaining = [f'"{r["title"]}"' for r in marketing_remaining]
        feedback_parts.append(
            f'✗ No marketing slides removed (0 pts). '
            f'Delete slides with employee testimonials or investment highlights: {"; ".join(remaining)}'
        )

    # 6. Slide count reasonable (10 pts)
    output_count = result.get('output_slide_count', 0)
    if 21 <= output_count <= 23:
        score += 10
        feedback_parts.append(
            f'✓ Output deck has {output_count} slides (expected 22 after removing 2 marketing slides) (+10 pts)'
        )
    elif output_count > 0:
        feedback_parts.append(
            f'~ Output deck has {output_count} slides (expected 21–23). '
            f'Original was 24; after removing 2 marketing slides should be ~22. (0 pts)'
        )

    passed = score >= 65

    return {
        'passed': passed,
        'score': score,
        'feedback': '\n'.join([
            f'Score: {score}/100  (pass threshold: 65)',
            f'Output: {output_count} slides',
            f'GRI codes fixed: {num_gri_fixed}/3',
            f'TCFD order correct: {"yes" if tcfd_correct and len(positions) == 4 else "no"}',
            f'Marketing slides removed: {num_mkt_removed}/2',
            '',
        ] + feedback_parts),
    }
