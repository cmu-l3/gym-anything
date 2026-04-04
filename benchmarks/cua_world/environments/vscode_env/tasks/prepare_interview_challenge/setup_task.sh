#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prepare Interview Challenge Task ==="

# Create empty workspace directory
WORKSPACE_DIR="/home/ga/workspace/interview_challenge"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo chown -R ga:ga "$WORKSPACE_DIR"

echo "Created empty workspace at: $WORKSPACE_DIR"

# Open VSCode with the empty workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Prepare Interview Challenge Task Setup Complete ==="
echo "📝 Scenario: You're conducting interviews tomorrow and need to prepare a Two Sum challenge"
echo ""
echo "Required Structure:"
echo "  interview_challenge/"
echo "  ├── .vscode/settings.json      (hide tests/ and evaluation/ folders)"
echo "  ├── challenge/solution.py      (Two Sum starter code with signature only)"
echo "  ├── tests/test_solution.py     (5+ test cases with pytest/unittest)"
echo "  ├── evaluation/rubric.md       (scoring criteria with points)"
echo "  └── README.md                   (problem description, examples, constraints)"
echo ""
echo "Key Requirements:"
echo "  - solution.py: 'def two_sum(nums: List[int], target: int) -> List[int]:' with docstring, no implementation"
echo "  - test_solution.py: ≥5 test cases covering edge cases"
echo "  - rubric.md: scoring criteria (correctness, efficiency, code quality) with point values"
echo "  - README.md: Two Sum problem description, example, constraints, 30 min time limit"
echo "  - settings.json: hide tests/ and evaluation/ folders via files.exclude"