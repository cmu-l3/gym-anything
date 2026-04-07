import json

data = {
    "task_id": "annual_compensation_adjustment@1",
    "dataset": None,
    "case_id": None,
    "data_is_synthetic": True,
    "pi_items": [
        {
            "key": "expected_updates",
            "metadata_value": '[{"empid": "EMP002", "salary": "115000", "bonus": "10500"}, {"empid": "EMP006", "salary": "132500", "bonus": "14000"}, {"empid": "EMP011", "salary": "98400", "bonus": "7200"}, {"empid": "EMP018", "salary": "145000", "bonus": "18500"}]',
            "verified_value": '[{"empid": "EMP002", "salary": "115000", "bonus": "10500"}, {"empid": "EMP006", "salary": "132500", "bonus": "14000"}, {"empid": "EMP011", "salary": "98400", "bonus": "7200"}, {"empid": "EMP018", "salary": "145000", "bonus": "18500"}]',
            "source": "setup_task.sh generating /home/ga/Desktop/q1_2026_comp_review.txt and verifier.py logic",
            "status": "verified"
        },
        {
            "key": "ignored_update",
            "metadata_value": '{"empid": "EMP014", "salary": "105000", "bonus": "5000"}',
            "verified_value": '{"empid": "EMP014", "salary": "105000", "bonus": "5000"}',
            "source": "setup_task.sh generating /home/ga/Desktop/q1_2026_comp_review.txt and verifier.py negative constraint logic",
            "status": "verified"
        }
    ],
    "privileged_info_summary": "The task operates on a synthetically seeded Sentrifugo database. I confirmed that the expected salary and bonus updates explicitly match the generated confidential memo and verifier logic. However, I discovered a significant contradiction: three of the employee names in the memo (EMP002 'Sarah Johnson', EMP011 'Daniel Wilson', and EMP014 'Thomas Moore') do not match the names seeded in the database (EMP002 is 'Sarah Mitchell', EMP011 is 'Matthew Garcia', EMP014 is 'Stephanie Brown'). An agent searching by name instead of Employee ID will find mismatched or no records.",
    "pi_confidence": "high"
}

with open('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/sentrifugo_env/tasks/annual_compensation_adjustment/validated_pi.json', 'w') as f:
    json.dump(data, f, indent=4)
