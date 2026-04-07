import json

with open("task.json", "r") as f:
    task_data = json.load(f)

metadata = task_data.get("metadata", {})

pi_items = [
    {
        "key": "expected_depth_m",
        "metadata_value": metadata.get("expected_depth_m"),
        "verified_value": 18.0,
        "source": "task.json description states 'Maximum depth: 18 meters'.",
        "status": "verified"
    },
    {
        "key": "expected_duration_min",
        "metadata_value": metadata.get("expected_duration_min"),
        "verified_value": 40.0,
        "source": "task.json description states 'Bottom time at maximum depth: 40 minutes'.",
        "status": "verified"
    },
    {
        "key": "expected_gas",
        "metadata_value": metadata.get("expected_gas"),
        "verified_value": "air",
        "source": "task.json description states 'Breathing gas: Air (21% O2)'.",
        "status": "verified"
    },
    {
        "key": "target_file",
        "metadata_value": metadata.get("target_file"),
        "verified_value": "/home/ga/Documents/dives.ssrf",
        "source": "task.json description states 'persist changes to /home/ga/Documents/dives.ssrf'.",
        "status": "verified"
    }
]

validated_pi = {
    "task_id": task_data["id"],
    "dataset": "SampleDivesV2.ssrf",
    "case_id": "plan_dive_with_planner",
    "data_is_synthetic": False,
    "pi_items": pi_items,
    "privileged_info_summary": "The task operates on real sample dive data (SampleDivesV2.ssrf) from the official Subsurface repository. The task requires the agent to generate a synthetic planned dive with the following parameters: 18.0m maximum depth, 40.0 minutes bottom time, and using air (21% O2) as the breathing gas. The final dive plan must be appended to the target file at /home/ga/Documents/dives.ssrf.",
    "pi_confidence": "high"
}

with open("validated_pi.json", "w") as f:
    json.dump(validated_pi, f, indent=4)

