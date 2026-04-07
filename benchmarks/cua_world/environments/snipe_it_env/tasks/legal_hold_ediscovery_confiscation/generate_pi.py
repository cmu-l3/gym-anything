import json

pi = {
    "task_id": "legal_hold_ediscovery_confiscation@1",
    "dataset": None,
    "case_id": None,
    "data_is_synthetic": True,
    "pi_items": [
        {
            "key": "occupation",
            "metadata_value": "IT Compliance Officer",
            "verified_value": None,
            "source": "Role flavor text; not empirically verifiable",
            "status": "unverified"
        },
        {
            "key": "industry",
            "metadata_value": "Legal Services",
            "verified_value": None,
            "source": "Role flavor text; not empirically verifiable",
            "status": "unverified"
        },
        {
            "key": "target_users",
            "metadata_value": "['Marcus Vance', 'Elena Rostova', 'David Chen']",
            "verified_value": "['Marcus Vance', 'Elena Rostova', 'David Chen']",
            "source": "setup_task.sh inject_user commands",
            "status": "verified"
        },
        {
            "key": "tracking_code",
            "metadata_value": "HOLD-2026-CHIMERA",
            "verified_value": "HOLD-2026-CHIMERA",
            "source": "task.json instructions explicitly demand this tracking code",
            "status": "verified"
        },
        {
            "key": "scoring_weights",
            "metadata_value": str({"c1_secure_location": 10, "c2_status_label": 10, "c3_asset_checkin": 20, "c4_status_update": 20, "c5_location_update": 10, "c6_chain_of_custody_note": 15, "c7_collateral_damage_prevented": 15}),
            "verified_value": None,
            "source": "No verifier.py present to confirm explicit scoring logic",
            "status": "unverified"
        }
    ],
    "privileged_info_summary": "The task data is synthetically generated via setup_task.sh, injecting target users Marcus Vance, Elena Rostova, and David Chen. The required tracking code 'HOLD-2026-CHIMERA' is explicitly mandated by the task description and verified against expected outputs.",
    "pi_confidence": "high"
}

with open('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/snipe_it_env/tasks/legal_hold_ediscovery_confiscation/validated_pi.json', 'w') as f:
    json.dump(pi, f, indent=4)

