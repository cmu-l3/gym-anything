import json
import tempfile
import os


def verify_statefulset_database_recovery(traj, env_info, task_info):
    """
    Verify that the agent recovered the broken postgres-primary StatefulSet.

    4 failures were injected; agent must fix at least 3 to pass (score >= 70):

    C1 (25 pts): At least 1 postgres-primary pod in Running state
        - This is the ultimate success indicator — pods running means all blockers cleared

    C2 (25 pts): PVC uses 'local-path' StorageClass (not the non-existent 'premium-ssd')
        - The agent must delete the bad PVC and/or recreate the StatefulSet with correct SC

    C3 (25 pts): StatefulSet references 'postgres-credentials' Secret (not 'postgres-db-secret')
        - The env vars must reference the correct secret that actually exists

    C4 (25 pts): Memory request is <= 4Gi (was injected as 32Gi, which causes Pending)
        - Agent must update the resource request to a schedulable value
    """
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {
            'passed': False,
            'score': 0,
            'reason': 'copy_from_env not available in env_info'
        }

    result_path = '/tmp/statefulset_database_recovery_result.json'
    score = 0
    details = []

    try:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name

        copy_from_env(result_path, tmp_path)

        with open(tmp_path, 'r') as f:
            result = json.load(f)

        os.unlink(tmp_path)

    except (FileNotFoundError, json.JSONDecodeError, Exception) as e:
        return {
            'passed': False,
            'score': 0,
            'reason': f'Failed to read result file: {e}',
            'details': []
        }

    # ── C1: At least 1 pod Running ────────────────────────────────────────────
    pods_running = result.get('pods_running', 0)
    c1_pass = pods_running >= 1

    if c1_pass:
        score += 25
        details.append(f'PASS (25 pts) C1: {pods_running} postgres-primary pod(s) in Running state')
    else:
        pods_phases = result.get('pods_phases', 'unknown')
        details.append(f'FAIL (0 pts) C1: No postgres-primary pods running '
                       f'(pods_total={result.get("pods_total", 0)}, phases={pods_phases})')

    # ── C2: StorageClass fixed (not premium-ssd) ──────────────────────────────
    pvc_has_premium_ssd = result.get('pvc_has_premium_ssd', True)
    postgres_pvc_sc = result.get('postgres_pvc_storageclass', 'premium-ssd')

    # Pass if: no PVC uses premium-ssd AND the postgres PVC uses local-path
    c2_pass = (
        not pvc_has_premium_ssd and
        postgres_pvc_sc == 'local-path'
    )

    if c2_pass:
        score += 25
        details.append(f'PASS (25 pts) C2: PVC StorageClass corrected to {postgres_pvc_sc}')
    else:
        if pvc_has_premium_ssd:
            details.append(f'FAIL (0 pts) C2: PVC still uses non-existent StorageClass '
                           f'"premium-ssd" (should be "local-path")')
        else:
            details.append(f'FAIL (0 pts) C2: PVC StorageClass is "{postgres_pvc_sc}" '
                           f'(expected "local-path")')

    # ── C3: Secret reference fixed ────────────────────────────────────────────
    wrong_secret_still_referenced = result.get('wrong_secret_still_referenced', True)
    correct_secret_referenced = result.get('correct_secret_referenced', False)
    correct_secret_exists = result.get('correct_secret_exists', False)

    # Pass if: correct secret is referenced AND wrong secret is no longer referenced
    c3_pass = correct_secret_referenced and not wrong_secret_still_referenced

    if c3_pass:
        score += 25
        details.append('PASS (25 pts) C3: StatefulSet correctly references '
                       '"postgres-credentials" Secret')
    else:
        if wrong_secret_still_referenced:
            details.append('FAIL (0 pts) C3: StatefulSet still references non-existent '
                           '"postgres-db-secret" (should reference "postgres-credentials")')
        elif not correct_secret_referenced:
            details.append('FAIL (0 pts) C3: StatefulSet does not reference '
                           '"postgres-credentials" Secret')
        else:
            details.append(f'FAIL (0 pts) C3: Secret reference issue '
                           f'(wrong_ref={wrong_secret_still_referenced}, '
                           f'correct_ref={correct_secret_referenced})')

    # ── C4: Memory request is schedulable (<= 4Gi) ────────────────────────────
    memory_request_gi = result.get('memory_request_gi', 999)
    memory_request = result.get('memory_request', 'unknown')

    # 4Gi threshold: 32Gi was injected; anything <= 4Gi is reasonable for a DB
    c4_pass = isinstance(memory_request_gi, (int, float)) and memory_request_gi <= 4.0

    if c4_pass:
        score += 25
        details.append(f'PASS (25 pts) C4: Memory request reduced to {memory_request} '
                       f'({memory_request_gi:.1f} Gi, within schedulable range)')
    else:
        details.append(f'FAIL (0 pts) C4: Memory request is {memory_request} '
                       f'({memory_request_gi} Gi) — too high (> 4Gi, was injected as 32Gi)')

    passed = score >= 70

    return {
        'passed': passed,
        'score': score,
        'reason': (f'Score {score}/100. {"PASSED" if passed else "FAILED"} (threshold: 70). '
                   f'{sum([c1_pass, c2_pass, c3_pass, c4_pass])}/4 failures remediated.'),
        'details': details,
        'raw': result
    }
