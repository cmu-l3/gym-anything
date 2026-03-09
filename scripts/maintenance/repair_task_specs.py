#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any, Dict, Optional


ROOT = Path("benchmarks/environments")


TASK_OVERRIDES: Dict[str, Dict[str, Any]] = {
    "aerobridge_env/tasks/calculate_operational_bounds": {
        "description_suffix": (
            "{\n"
            '  "min_lat": <float>,\n'
            '  "max_lat": <float>,\n'
            '  "min_lon": <float>,\n'
            '  "max_lon": <float>\n'
            "}\n"
        ),
        "metadata": {"tolerance_degrees": 0.0001},
    },
    "android_studio_env/tasks/configure_product_flavors": {
        "description_suffix": (
            "<resources>\n"
            '    <string name="app_name">Todo Free</string>\n'
            "</resources>\n\n"
            "3. Create the paid flavor resource file at "
            "`app/src/paid/res/values/strings.xml` with:\n\n"
            "<resources>\n"
            '    <string name="app_name">Todo Pro</string>\n'
            "</resources>\n"
        ),
    },
    "blue_sky_plan_env/tasks/classify_bone_quality_misch": {
        "description_suffix": (
            "Site #3: <HU> - <D1|D2|D3|D4>\n"
            "Site #8: <HU> - <D1|D2|D3|D4>\n"
            "Site #19: <HU> - <D1|D2|D3|D4>\n"
            "Site #30: <HU> - <D1|D2|D3|D4>\n"
        ),
    },
    "jamovi_env/tasks/logistic_prediction_analysis_titanic": {
        "description_suffix": (
            "No: <mean_probability>\n"
            "Yes: <mean_probability>\n"
        ),
        "metadata": {
            "expected_omv_path": "/home/ga/Documents/Jamovi/Titanic_Predictions.omv",
            "ground_truth": {
                "mean_prob_no_min": 0.20,
                "mean_prob_no_max": 0.30,
                "mean_prob_yes_min": 0.58,
                "mean_prob_yes_max": 0.68,
            },
        },
    },
    "liverpool_cancer_ichart_env/tasks/screen_admission_meds_ceritinib": {
        "description_suffix": (
            "Rifampicin,<Color>\n"
            "Warfarin,<Color>\n"
            "Midazolam,<Color>\n"
            "Metformin,<Color>\n"
        ),
        "metadata": {
            "required_drugs": ["Rifampicin", "Warfarin", "Midazolam", "Metformin"],
            "valid_colors": ["Red", "Orange", "Yellow", "Green", "Grey", "Gray"],
        },
    },
    "liverpool_cancer_ichart_env/tasks/select_safer_gout_medication_mercaptopurine": {
        "description_suffix": (
            "Mercaptopurine + Allopurinol: <Color>\n"
            "Mercaptopurine + Colchicine: <Color>\n"
            "Recommendation: <Drug Name>\n"
        ),
    },
    "liverpool_cancer_ichart_env/tasks/select_safer_muscle_relaxant_rucaparib": {
        "description_suffix": (
            "Rucaparib + Tizanidine: <Color>\n"
            "Rucaparib + Baclofen: <Color>\n"
            "Safer Choice: <Drug Name>\n"
        ),
    },
    "woo_commerce_env/tasks/customize_transactional_email": {
        "description_suffix": (
            "Use two short lines of customer-facing delivery copy in the Additional content field, "
            "then save the email settings.\n"
        ),
        "metadata": {
            "expected_subject": "Your package has arrived! 📦",
            "expected_heading": "Hooray! Order #{order_number} is complete",
        },
    },
}


def _mode(values: Counter[Any], default: Any) -> Any:
    if not values:
        return default
    return values.most_common(1)[0][0]


def infer_env_defaults(env_dir: Path) -> Dict[str, Any]:
    difficulties: Counter[str] = Counter()
    timeouts: Counter[int] = Counter()
    max_steps: Counter[int] = Counter()
    reward_types: Counter[str] = Counter()

    for task_path in sorted((env_dir / "tasks").glob("*/task.json")):
        try:
            data = json.loads(task_path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if data.get("difficulty"):
            difficulties[data["difficulty"]] += 1
        init = data.get("init", {})
        if "timeout_sec" in init:
            timeouts[int(init["timeout_sec"])] += 1
        if "max_steps" in init:
            max_steps[int(init["max_steps"])] += 1
        if "reward_type" in init:
            reward_types[str(init["reward_type"])] += 1

    return {
        "difficulty": _mode(difficulties, None),
        "init": {
            "timeout_sec": _mode(timeouts, 600),
            "max_steps": _mode(max_steps, 2000),
            "reward_type": _mode(reward_types, "sparse"),
        },
    }


def parse_truncated_task(path: Path) -> Dict[str, str]:
    raw = path.read_text(encoding="utf-8")
    parsed: Dict[str, str] = {}
    for key in ("id", "version", "env_id"):
        match = re.search(rf'"{key}"\s*:\s*"([^"]*)"', raw)
        if not match:
            raise ValueError(f"Could not recover '{key}' from {path}")
        parsed[key] = match.group(1)

    desc_match = re.search(r'"description"\s*:\s*"(.*)\Z', raw, re.S)
    if not desc_match:
        raise ValueError(f"Could not recover description from {path}")
    desc_fragment = desc_match.group(1).rstrip()
    parsed["description"] = json.loads(f'"{desc_fragment}"')
    return parsed


def infer_hooks(task_dir: Path) -> Dict[str, str]:
    hooks: Dict[str, str] = {}
    setup = sorted(task_dir.glob("setup_task.*"))
    export = sorted(task_dir.glob("export_result.*"))
    if setup:
        hooks["pre_task"] = f"/workspace/tasks/{task_dir.name}/{setup[0].name}"
    if export:
        hooks["post_task"] = f"/workspace/tasks/{task_dir.name}/{export[0].name}"
    return hooks


def infer_program_target(task_dir: Path) -> Optional[str]:
    verifier = task_dir / "verifier.py"
    if not verifier.exists():
        return None
    text = verifier.read_text(encoding="utf-8", errors="ignore")
    matches = re.findall(r"^def\s+(verify_[A-Za-z0-9_]+|verify)\s*\(", text, re.M)
    if not matches:
        return None
    return f"verifier.py::{matches[0]}"


def needs_repair(task_path: Path) -> bool:
    try:
        json.loads(task_path.read_text(encoding="utf-8"))
        return False
    except json.JSONDecodeError:
        return True


def build_repaired_task(task_path: Path) -> Dict[str, Any]:
    task_dir = task_path.parent
    env_dir = task_dir.parent.parent
    rel_task_dir = str(task_dir.relative_to(ROOT))
    recovered = parse_truncated_task(task_path)
    defaults = infer_env_defaults(env_dir)
    overrides = TASK_OVERRIDES.get(rel_task_dir, {})

    description = recovered["description"]
    suffix = overrides.get("description_suffix")
    if suffix and description.rstrip().endswith(":"):
        description = f"{description}{suffix}"

    data: Dict[str, Any] = {
        "id": recovered["id"],
        "version": recovered["version"],
        "env_id": recovered["env_id"],
        "description": description,
        "init": defaults["init"],
    }
    if defaults["difficulty"]:
        data["difficulty"] = defaults["difficulty"]

    hooks = infer_hooks(task_dir)
    if hooks:
        data["hooks"] = hooks

    metadata = dict(overrides.get("metadata", {}))
    if metadata:
        data["metadata"] = metadata

    program_target = infer_program_target(task_dir)
    if program_target:
        data["success"] = {"mode": "program", "spec": {"program": program_target}}
    else:
        raise ValueError(f"Could not infer verifier target for {task_dir}")
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair malformed task.json files in benchmarks/environments")
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    root = Path(args.root)
    repaired = 0
    for task_path in sorted(root.glob("*/tasks/*/task.json")):
        if not needs_repair(task_path):
            continue
        data = build_repaired_task(task_path)
        repaired += 1
        if args.write:
            task_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        else:
            print(task_path)
            print(json.dumps(data, indent=2, ensure_ascii=False))
    print(f"repaired_candidates={repaired}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
