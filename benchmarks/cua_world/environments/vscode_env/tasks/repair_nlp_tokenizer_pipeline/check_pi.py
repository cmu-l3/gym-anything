import json

with open('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/vscode_env/tasks/repair_nlp_tokenizer_pipeline/task.json') as f:
    task = json.load(f)

metadata = task['metadata']
for k, v in metadata.items():
    print(f"{k}: {v}")
