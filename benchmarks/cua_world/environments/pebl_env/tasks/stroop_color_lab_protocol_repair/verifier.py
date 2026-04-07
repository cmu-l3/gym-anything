"""
Verifier for stroop_color_lab_protocol_repair task.

Scoring (100 pts total):
  1. File is valid JSON                            (10 pts)
  2. practice_trials == 12                         (15 pts)
  3. test_trials_per_block == 48                   (15 pts)
  4. blocks == 4                                   (20 pts)
  5. isi_ms == 500                                 (15 pts)
  6. response_colors == ["red","blue","green","yellow"] in any order  (25 pts)

Pass threshold: 60 pts

Injected wrong values:
  practice_trials: 20    (correct: 12)
  test_trials_per_block: 36  (correct: 48)
  blocks: 6              (correct: 4)
  isi_ms: 750            (correct: 500)
  response_colors: ["red","blue","green","purple"]  (correct: [...,"yellow"])
"""

import json
import os
import tempfile

CORRECT_PRACTICE_TRIALS = 12
CORRECT_TEST_TRIALS_PER_BLOCK = 48
CORRECT_BLOCKS = 4
CORRECT_ISI_MS = 500
CORRECT_RESPONSE_COLORS = {'red', 'blue', 'green', 'yellow'}
PASS_THRESHOLD = 60

# Initial wrong values (for do-nothing detection)
WRONG_PRACTICE_TRIALS = 20
WRONG_TEST_TRIALS = 36
WRONG_BLOCKS = 6
WRONG_ISI = 750
WRONG_COLORS = {'red', 'blue', 'green', 'purple'}


def verify_stroop_color_lab_protocol_repair(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # --- Criterion 1: File exists and is valid JSON ---
    data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/lab/stroop_protocol.json', tmp_path)
        with open(tmp_path, encoding='utf-8') as f:
            data = json.load(f)
        score += 10
        feedback_parts.append('[+10] Protocol file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Protocol file /home/ga/pebl/lab/stroop_protocol.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Protocol file is not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    params = data.get('parameters', {})
    if not isinstance(params, dict):
        feedback_parts.append('[0] "parameters" key missing or not an object.')
        return {'passed': False, 'score': score, 'feedback': ' '.join(feedback_parts)}

    # --- Criterion 2: practice_trials == 12 ---
    pt = params.get('practice_trials')
    if pt is not None:
        try:
            if int(pt) == CORRECT_PRACTICE_TRIALS:
                score += 15
                feedback_parts.append(f'[+15] practice_trials={pt} is correct.')
            else:
                feedback_parts.append(f'[0] practice_trials={pt}, expected {CORRECT_PRACTICE_TRIALS}.')
        except (TypeError, ValueError):
            feedback_parts.append(f'[0] practice_trials value "{pt}" is not an integer.')
    else:
        feedback_parts.append('[0] practice_trials key missing from parameters.')

    # --- Criterion 3: test_trials_per_block == 48 ---
    ttb = params.get('test_trials_per_block')
    if ttb is not None:
        try:
            if int(ttb) == CORRECT_TEST_TRIALS_PER_BLOCK:
                score += 15
                feedback_parts.append(f'[+15] test_trials_per_block={ttb} is correct.')
            else:
                feedback_parts.append(f'[0] test_trials_per_block={ttb}, expected {CORRECT_TEST_TRIALS_PER_BLOCK}.')
        except (TypeError, ValueError):
            feedback_parts.append(f'[0] test_trials_per_block value "{ttb}" is not an integer.')
    else:
        feedback_parts.append('[0] test_trials_per_block key missing from parameters.')

    # --- Criterion 4: blocks == 4 ---
    blks = params.get('blocks')
    if blks is not None:
        try:
            if int(blks) == CORRECT_BLOCKS:
                score += 20
                feedback_parts.append(f'[+20] blocks={blks} is correct.')
            else:
                feedback_parts.append(f'[0] blocks={blks}, expected {CORRECT_BLOCKS}.')
        except (TypeError, ValueError):
            feedback_parts.append(f'[0] blocks value "{blks}" is not an integer.')
    else:
        feedback_parts.append('[0] blocks key missing from parameters.')

    # --- Criterion 5: isi_ms == 500 ---
    isi = params.get('isi_ms')
    if isi is not None:
        try:
            if int(isi) == CORRECT_ISI_MS:
                score += 15
                feedback_parts.append(f'[+15] isi_ms={isi} is correct.')
            else:
                feedback_parts.append(f'[0] isi_ms={isi}, expected {CORRECT_ISI_MS}.')
        except (TypeError, ValueError):
            feedback_parts.append(f'[0] isi_ms value "{isi}" is not an integer.')
    else:
        feedback_parts.append('[0] isi_ms key missing from parameters.')

    # --- Criterion 6: response_colors correct ---
    rc = params.get('response_colors')
    if rc is not None and isinstance(rc, list):
        rc_set = {str(c).lower().strip() for c in rc}
        if rc_set == CORRECT_RESPONSE_COLORS:
            score += 25
            feedback_parts.append(f'[+25] response_colors={rc} is correct.')
        elif 'yellow' in rc_set and 'purple' not in rc_set:
            partial = 12
            score += partial
            feedback_parts.append(f'[+{partial}] response_colors contains yellow (purple removed) but may have other issues: {rc}.')
        else:
            feedback_parts.append(f'[0] response_colors={rc}, expected {sorted(CORRECT_RESPONSE_COLORS)}.')
    else:
        feedback_parts.append('[0] response_colors key missing or not a list.')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }
