"""
VLM Checklist Trajectory Verifier (Stages 2 + 3)

Stage 2: Auto-generates structured verification checklists from task.json +
task metadata.
Stage 3: Scores trajectories against checklists using VLM.

Usage:
    python tools/verification/vlm_checklist_verifier.py <run_folder> <env_name> [--vlm-model MODEL] [--regenerate-checklists]

Examples:
    python tools/verification/vlm_checklist_verifier.py gemini3_pro_runs slicer3d_env_final
    python tools/verification/vlm_checklist_verifier.py gemini3_pro_runs slicer3d_env_final --vlm-model gemini-3-flash-preview
    python tools/verification/vlm_checklist_verifier.py gemini3_pro_runs slicer3d_env_final --regenerate-checklists
"""

from pathlib import Path
import sys

_repo_root = Path(__file__).resolve().parents[2]
if str(_repo_root) not in sys.path:
    sys.path.insert(0, str(_repo_root))
_src_dir = _repo_root / "src"
if _src_dir.is_dir() and str(_src_dir) not in sys.path:
    sys.path.insert(0, str(_src_dir))

from PIL import Image
from io import BytesIO
import base64
import json
import os
import sys
import argparse
import time
from glob import glob
from tqdm import tqdm
import multiprocessing
from dotenv import load_dotenv

load_dotenv()

from baselines.common.llm_clients import call_gemini_with_retry


# ============================================================
# Image encoding (reused from verify_all_tasks_gemini.py)
# ============================================================

def encode_image(image_path):
    """Encode image to base64 data URI for VLM consumption."""
    from PIL import ImageFile
    ImageFile.LOAD_TRUNCATED_IMAGES = True
    try:
        image = Image.open(image_path)
        buffer = BytesIO()
        image.save(buffer, format="PNG")
        processed_bytes = buffer.getvalue()
        return f'data:image/png;base64,{base64.b64encode(processed_bytes).decode("utf-8")}'
    except Exception:
        return None


# ============================================================
# Stage 2: Checklist Generation
# ============================================================

def generate_checklist(task_json, validated_pi, model):
    """Use LLM to generate a structured verification checklist from task + PI."""

    task_desc = task_json.get('description', '')
    task_id = task_json.get('id', 'unknown')
    metadata = task_json.get('metadata', {})
    scoring_weights = metadata.get('scoring_weights', None)

    pi_summary = "No verified privileged information available."
    if validated_pi and validated_pi.get('privileged_info_summary'):
        pi_summary = validated_pi['privileged_info_summary']

    pi_items_text = ""
    if validated_pi and validated_pi.get('pi_items'):
        verified_items = [item for item in validated_pi['pi_items'] if item.get('status') == 'verified']
        if verified_items:
            pi_items_text = f"\nVerified PI items:\n{json.dumps(verified_items, indent=2)}"

    scoring_text = ""
    if scoring_weights:
        scoring_text = f"\nExisting scoring weights from task.json (use as guidance for point allocation):\n{json.dumps(scoring_weights, indent=2)}"

    prompt = f"""You are generating a verification checklist for an AI agent benchmark task. This checklist will be used by a VLM (vision-language model) to score agent trajectories by examining screenshots.

Task ID: {task_id}
Task Description: {task_desc}

Metadata keys: {json.dumps(list(metadata.keys()))}
{scoring_text}

Privileged Information: {pi_summary}
{pi_items_text}

Generate a checklist with two sections:

1. **task_completion** (5-8 items, points must sum to exactly 100):
   Each item represents a sub-goal or evidence of progress. Items should be ordered from earliest to latest.
   - CRITICAL: ONLY include items that are explicitly required by the task description. Do NOT add steps like or any action not mentioned in the task description.
   - Assign more points to harder items
   - Each item must be visually verifiable from screenshots
   - Include what visual evidence the VLM should look for
   - After creating a preliminary checklist, ask yourself, "are all checklist items required by the task description?" If not, remove the items that are not required.

2. **integrity** (3-4 items):
   Each item checks for cheating/shortcuts. Common integrity checks:
   - Agent used the GUI, not terminal commands to generate outputs
   - Agent interacted with the actual application (not a text editor)
   - Agent didn't copy-paste expected answers from the task description
   - Results appear to come from genuine software interaction

Also produce a `privileged_info_for_vlm` field: a concise text with ONLY verified facts that helps the VLM judge correctness. If no PI is verified, write "No privileged information available."

Respond with ONLY a JSON object (no markdown fencing):
{{
    "task_id": "{task_id}",
    "task_completion": [
        {{
            "id": "short_snake_case_id",
            "description": "What this item checks",
            "points": 20,
            "visual_evidence": "What the VLM should look for in screenshots"
        }}
    ],
    "integrity": [
        {{
            "id": "short_snake_case_id",
            "description": "What this integrity check verifies",
            "visual_evidence": "What the VLM should look for"
        }}
    ],
    "privileged_info_for_vlm": "Verified facts for the VLM verifier"
}}"""

    messages = [{"role": "user", "content": prompt}]
    raw_response = call_gemini_with_retry(
        messages, model, temperature=0.3, top_p=0.95, max_tokens=4096, reasoning_effort='high', timeout=120
    )

    # Log raw response
    log_dir = os.path.join('logs', 'checklist_generation')
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, f'{task_json.get("id", "unknown").replace("@", "_")}_{model}.txt')
    with open(log_path, 'w') as f:
        f.write(raw_response or '')

    response = raw_response or ''
    if '</think>' in response:
        response = response.split('</think>')[-1].strip()

    try:
        if '```json' in response:
            response = response.split('```json')[1].split('```')[0].strip()
        elif '```' in response:
            response = response.split('```')[1].split('```')[0].strip()
        checklist = json.loads(response)

        # Validate: points must sum to 100
        total_points = sum(item.get('points', 0) for item in checklist.get('task_completion', []))
        if total_points != 100:
            print(f"  Warning: checklist points sum to {total_points}, expected 100. Normalizing...")
            if total_points > 0:
                for item in checklist['task_completion']:
                    item['points'] = round(item['points'] * 100 / total_points)
                # Fix rounding: adjust last item
                actual_sum = sum(item['points'] for item in checklist['task_completion'])
                if actual_sum != 100:
                    checklist['task_completion'][-1]['points'] += (100 - actual_sum)

        return checklist
    except json.JSONDecodeError as e:
        print(f"  Checklist generation JSON parse error: {e}")
        print(f"  Raw: {response[:500]}")
        return None


def _load_validated_pi(task_dir):
    """Load task metadata from the canonical location with legacy fallback."""
    candidates = [
        os.path.join(task_dir, 'metadata', 'validated_pi.json'),
        os.path.join(task_dir, 'validated_pi.json'),
    ]
    for pi_path in candidates:
        if os.path.exists(pi_path):
            with open(pi_path) as f:
                return json.load(f)
    return None


def get_or_load_checklist(task_name, env_name, model, force_regenerate=False):
    """Load cached checklist or generate a new one."""
    task_dir = os.path.join('benchmarks', 'environments', env_name, 'tasks', task_name)
    checklist_path = os.path.join(task_dir, 'vlm_checklist.json')

    if not force_regenerate and os.path.exists(checklist_path):
        with open(checklist_path) as f:
            return json.load(f)

    # Load task.json
    task_json_path = os.path.join(task_dir, 'task.json')
    if not os.path.exists(task_json_path):
        return None
    with open(task_json_path) as f:
        task_json = json.load(f)

    validated_pi = _load_validated_pi(task_dir)

    checklist = generate_checklist(task_json, validated_pi, model)

    if checklist:
        with open(checklist_path, 'w') as f:
            json.dump(checklist, f, indent=2)

    return checklist


# ============================================================
# Stage 3: Trajectory Verification
# ============================================================

def build_verification_prompt(checklist, task_desc, images):
    """Build the VLM prompt for trajectory verification."""

    pi_text = checklist.get('privileged_info_for_vlm', 'No privileged information available.')

    # Format checklist items
    completion_items = []
    for item in checklist.get('task_completion', []):
        completion_items.append(
            f"  - [{item['id']}] ({item['points']} pts): {item['description']}\n"
            f"    Visual evidence: {item['visual_evidence']}"
        )

    integrity_items = []
    for item in checklist.get('integrity', []):
        integrity_items.append(
            f"  - [{item['id']}]: {item['description']}\n"
            f"    Visual evidence: {item['visual_evidence']}"
        )

    system_msg = """You are an expert evaluator scoring AI agent trajectories on computer-use benchmark tasks.
You will examine trajectory screenshots and score the agent's work against a structured checklist.

SCORING RULES:
- For each task_completion item: "pass" (full points), "partial" (half points), or "fail" (0 points)
- For each integrity item: "pass" or "fail"
- Be strict: only give "pass" if you see clear visual evidence
- "partial" is for when the agent made meaningful progress but didn't fully complete the sub-task
- Provide specific evidence from the screenshots for each verdict

INTEGRITY CHECK RULES (critical - read carefully):
- Integrity checks detect CHEATING or SHORTCUTS, NOT task failure.
- An agent that genuinely attempted the task but failed, produced no output, or got empty/wrong results is an INTEGRITY PASS - honest failure is not cheating.
- Only mark integrity FAIL if you see clear evidence of: hardcoding answers, copy-pasting expected values from the task description, fabricating results without using the software, or bypassing the required workflow entirely (e.g. writing a fake output file by hand).
- If the agent attempted the correct workflow but simply could not complete it, that is a task_completion failure - score it there. The integrity item should still PASS."""

    user_content = [
        {
            'type': 'text',
            'text': f"""Task Description: {task_desc}

Privileged Information (verified facts): {pi_text}

=== TASK COMPLETION CHECKLIST (score each item) ===
{chr(10).join(completion_items)}

=== INTEGRITY CHECKS (pass/fail each item) ===
REMINDER: Integrity = detecting cheating/shortcuts only. Genuine failure or empty output = PASS. Fabricated/hardcoded output = FAIL.
{chr(10).join(integrity_items)}

Below are screenshots from the agent's trajectory (first 3 frames, every 3rd middle frame, last 3 frames).
Examine them carefully and score each checklist item."""
        }
    ]

    # Add images (skip corrupt/truncated ones)
    for img_path in images[:3] + images[3:-3][::3] + images[-3:]:
        encoded = encode_image(img_path)
        if encoded:
            user_content.append({
                'type': 'image_url',
                'image_url': {'url': encoded}
            })

    user_content.append({
        'type': 'text',
        'text': """Now score each checklist item. Respond with ONLY a JSON object (no markdown fencing):
{
    "task_completion": [
        {"id": "item_id", "verdict": "pass|partial|fail", "confidence": 0.0-1.0, "evidence": "what you see"}
    ],
    "integrity": [
        {"id": "item_id", "verdict": "pass|fail", "confidence": 0.0-1.0, "evidence": "what you see"}
    ],
    "overall_reasoning": "1-3 sentence summary of what the agent did and how well it performed"
}"""
    })

    messages = [
        {'role': 'system', 'content': system_msg},
        {'role': 'user', 'content': user_content}
    ]

    return messages


def parse_verification_response(response):
    """Parse VLM JSON response into structured verdicts."""
    if '</think>' in response:
        response = response.split('</think>')[-1].strip()

    try:
        if '```json' in response:
            response = response.split('```json')[1].split('```')[0].strip()
        elif '```' in response:
            response = response.split('```')[1].split('```')[0].strip()
        return json.loads(response)
    except json.JSONDecodeError as e:
        print(f"  Verification response parse error: {e}")
        return None


def compute_scores(verdicts, checklist):
    """Compute Score A (completion) and Score B (integrity) from verdicts."""
    if not verdicts:
        return {'score_a': 0, 'score_b': False, 'final_score': 0, 'error': 'No verdicts parsed'}

    # Score A: task completion (0-100)
    score_a = 0
    completion_details = []
    verdict_map = {v['id']: v for v in verdicts.get('task_completion', [])}

    for item in checklist.get('task_completion', []):
        item_id = item['id']
        points = item.get('points', 0)
        v = verdict_map.get(item_id, {})
        verdict = v.get('verdict', 'fail')

        if verdict == 'pass':
            earned = points
        elif verdict == 'partial':
            earned = points * 0.5
        else:
            earned = 0

        score_a += earned
        completion_details.append({
            'id': item_id,
            'max_points': points,
            'earned': earned,
            'verdict': verdict,
            'confidence': v.get('confidence', 0),
            'evidence': v.get('evidence', '')
        })

    # Score B: integrity (binary threshold: >= 75% pass)
    integrity_details = []
    integrity_verdicts = verdicts.get('integrity', [])
    n_integrity_pass = 0
    n_integrity_total = len(checklist.get('integrity', []))

    verdict_map_b = {v['id']: v for v in integrity_verdicts}
    for item in checklist.get('integrity', []):
        item_id = item['id']
        v = verdict_map_b.get(item_id, {})
        verdict = v.get('verdict', 'fail')
        if verdict == 'pass':
            n_integrity_pass += 1
        integrity_details.append({
            'id': item_id,
            'verdict': verdict,
            'confidence': v.get('confidence', 0),
            'evidence': v.get('evidence', '')
        })

    score_b = (n_integrity_pass / n_integrity_total >= 0.75) if n_integrity_total > 0 else True

    # Final: binary_threshold(B) * A
    final_score = score_a if score_b else 0

    return {
        'score_a': round(score_a, 1),
        'score_b': score_b,
        'integrity_pass_rate': f"{n_integrity_pass}/{n_integrity_total}",
        'final_score': round(final_score, 1),
        'completion_details': completion_details,
        'integrity_details': integrity_details,
        'overall_reasoning': verdicts.get('overall_reasoning', '')
    }


def verify_single_run(folder, env_name, vlm_model, checklist_model, force_regenerate_checklists=False):
    """Verify a single run against its task's checklist."""
    task_name = folder.split('/')[-3]

    try:
        # Load run data
        images = sorted(
            glob(os.path.join(folder, 'observation_*.png')),
            key=lambda x: int(x.split('_')[-1].split('.')[0])
        )
        if not images:
            return ''

        # Require responses.json and info.json to exist (matching verify_all_tasks_gemini.py)
        responses_path = os.path.join(folder, 'responses.json')
        json.load(open(responses_path))

        info_path = os.path.join(folder, 'info.json')
        info = json.load(open(info_path))
        if 'vlm_checklist_verifier' in info and not force_regenerate_checklists:
            return ''

        task_json_path = os.path.join('examples', env_name, 'tasks', task_name, 'task.json')
        with open(task_json_path) as f:
            task_json = json.load(f)
        task_desc = task_json.get('description', '')

    except (FileNotFoundError, json.JSONDecodeError):
        return ''

    # Get or generate checklist (Stage 2)
    checklist = get_or_load_checklist(task_name, env_name, checklist_model, force_regenerate_checklists)
    if not checklist:
        print(f"  [{task_name}] Failed to get checklist")
        return ''

    # Build prompt and call VLM (Stage 3)
    messages = build_verification_prompt(checklist, task_desc, images)

    verdicts = None
    full_response = ''
    for retry in range(3):
        try:
            full_response = call_gemini_with_retry(
                messages, vlm_model, temperature=0.5, top_p=0.95, max_tokens=4096,
                reasoning_effort='high', timeout=180
            )
            verdicts = parse_verification_response(full_response)
            if verdicts:
                break
        except Exception as e:
            print(f"  [{task_name}] Retry {retry}: {e}")
            time.sleep(retry ** 2 * 5)

    # Compute scores
    scores = compute_scores(verdicts, checklist)

    # Save to info.json
    info['vlm_checklist_verifier'] = {
        'model': vlm_model,
        'checklist_model': checklist_model,
        'scores': scores,
        'full_response': full_response,
    }

    with open(info_path, 'w') as f:
        json.dump(info, f, indent=4)

    final = scores.get('final_score', 0)
    score_a = scores.get('score_a', 0)
    score_b = scores.get('score_b', False)
    print(f"  [{task_name}] final={final} (A={score_a}, B={'pass' if score_b else 'FAIL'})")

    return full_response


def _verify_wrapper(folder):
    """Module-level wrapper for multiprocessing (local functions can't be pickled)."""
    return verify_single_run(folder, _mp_env_name, _mp_vlm_model, _mp_checklist_model, _mp_regen)


def _checklist_wrapper(task_name):
    """Module-level wrapper for checklist-only multiprocessing."""
    result = get_or_load_checklist(task_name, _mp_env_name, _mp_checklist_model, _mp_regen)
    if result:
        print(f"  [{task_name}] checklist ready ({len(result.get('task_completion', []))} items)")
    else:
        print(f"  [{task_name}] FAILED")
    return task_name, result is not None


def main():
    parser = argparse.ArgumentParser(description='VLM Checklist Trajectory Verifier')
    parser.add_argument('run_folder', nargs='?', default=None, help='Run folder path under all_runs/ (not needed with --checklists-only)')
    parser.add_argument('env_name', help='Environment name (e.g., slicer3d_env_final)')
    parser.add_argument('--vlm-model', default='gemini-3-flash-preview', help='VLM model for trajectory scoring')
    parser.add_argument('--checklist-model', default='gemini-3-pro-preview', help='Model for checklist generation')
    parser.add_argument('--regenerate-checklists', action='store_true', help='Force regenerate all checklists')
    parser.add_argument('--checklists-only', action='store_true', help='Only generate checklists (no run folders needed)')
    parser.add_argument('--workers', type=int, default=16, help='Number of parallel workers')
    parser.add_argument('--tasks', default=None, help='Comma-separated list of task names to verify')
    args = parser.parse_args()

    # Store args in module-level globals for multiprocessing pickling
    global _mp_env_name, _mp_vlm_model, _mp_checklist_model, _mp_regen
    _mp_env_name = args.env_name
    _mp_vlm_model = args.vlm_model
    _mp_checklist_model = args.checklist_model
    _mp_regen = args.regenerate_checklists

    # ---- Checklists-only mode: generate checklists without run folders ----
    if args.checklists_only:
        tasks_dir = os.path.join('examples', args.env_name, 'tasks')
        if not os.path.isdir(tasks_dir):
            print(f"Tasks directory not found: {tasks_dir}")
            sys.exit(1)

        task_names = sorted([
            d for d in os.listdir(tasks_dir)
            if os.path.isfile(os.path.join(tasks_dir, d, 'task.json'))
        ])

        if args.tasks:
            task_set = set(t.strip() for t in args.tasks.split(','))
            task_names = [t for t in task_names if t in task_set]

        print(f"Generating checklists for {len(task_names)} tasks in {args.env_name} with model={args.checklist_model}")

        with multiprocessing.Pool(args.workers) as pool:
            results = list(tqdm(
                pool.imap(_checklist_wrapper, task_names),
                total=len(task_names),
                desc="Checklists"
            ))

        success = sum(1 for _, ok in results if ok)
        print(f"\nGenerated {success}/{len(results)} checklists")
        return

    # ---- Normal mode: verify trajectories ----
    if not args.run_folder:
        print("Error: run_folder is required when not using --checklists-only")
        sys.exit(1)

    # Find run folders
    folders = glob(f'all_runs/{args.run_folder}/*/*/run_*/')
    if not folders:
        folders = glob(f'all_runs/{args.run_folder}/*/*/*/run_*/')
    if not folders:
        print(f"No run folders found for {args.run_folder}")
        sys.exit(1)

    # Filter by task names if specified
    if args.tasks:
        task_set = set(t.strip() for t in args.tasks.split(','))
        folders = [f for f in folders if f.split('/')[-3] in task_set]

    print(f"Verifying {len(folders)} runs in {args.env_name} with vlm={args.vlm_model}")

    with multiprocessing.Pool(args.workers) as pool:
        results = list(tqdm(
            pool.imap(_verify_wrapper, sorted(folders)),
            total=len(folders),
            desc="Verifying"
        ))

    # Summary
    verified_count = sum(1 for r in results if r)
    print(f"\nVerified {verified_count} new runs (skipped {len(results) - verified_count} already-verified)")


if __name__ == '__main__':
    main()
