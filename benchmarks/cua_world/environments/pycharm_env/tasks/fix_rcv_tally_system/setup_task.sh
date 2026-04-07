#!/bin/bash
echo "=== Setting up fix_rcv_tally_system task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_rcv_tally_system"
PROJECT_DIR="/home/ga/PycharmProjects/rcv_tally"

# Clean up any previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/tally $PROJECT_DIR/tests $PROJECT_DIR/data"

# --- Requirements ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
pandas>=2.0.0
EOF

# --- Data Generation ---
# Scenario:
# 10 ballots total.
# Round 1:
#   Alice: 4 (40%)
#   Bob: 3 (30%)
#   Charlie: 2 (20%)
#   Dave: 1 (10%)
#
# Round 2 (Dave eliminated):
#   Dave's voter picked Charlie next.
#   Alice: 4
#   Bob: 3
#   Charlie: 3
#   (Tie for elimination between Bob and Charlie? Let's make it simpler)
#
# Let's construct a specific case where the bugs matter.
# Bug 1 (Case Sensitivity): "alice" vs "Alice" splits her vote.
# Bug 2 (Transfer): When Dave is eliminated, if his voter's next choice was ALREADY eliminated (say, Eve), the system should skip Eve and go to the next.
# Bug 3 (Threshold): If ballots exhaust, the threshold for 50% drops.

cat > "$PROJECT_DIR/data/election_2024.csv" << 'EOF'
ballot_id,rank1,rank2,rank3
1,Alice,Bob,Charlie
2,Alice,Charlie,Bob
3,alice,Bob,Charlie
4,Bob,Alice,Charlie
5,Bob,Charlie,Alice
6,Charlie,Bob,Alice
7,Dave,Eve,Alice
8,Eve,Dave,Bob
9,Dave,Bob,Alice
10,Eve,Charlie,Alice
EOF
# Notes on data:
# Ballot 3 uses lowercase "alice" -> if not normalized, Alice loses a vote.
# Ballot 7: Dave -> Eve -> Alice.
# If Dave is eliminated 1st, and Eve is eliminated 2nd.
# When Eve is eliminated, her votes go to Dave (who is already gone). Buggy code might give to Dave or crash. Correct code skips Dave.
# Ballot 8: Eve -> Dave -> Bob. Same issue.

# --- tally/__init__.py ---
touch "$PROJECT_DIR/tally/__init__.py"

# --- tally/loader.py (Buggy) ---
cat > "$PROJECT_DIR/tally/loader.py" << 'EOF'
"""
Module for loading and normalizing ballot data.
"""
import csv
from typing import List, Dict

def load_ballots(filepath: str) -> List[List[str]]:
    """
    Load ballots from a CSV file.
    Returns a list of lists, where each inner list is a ranked sequence of candidate names.
    Example: [['Alice', 'Bob'], ['Bob', 'Charlie']]
    """
    ballots = []
    try:
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # Extract ranks rank1, rank2, etc.
                ranked_candidates = []
                # We assume columns are rank1, rank2, ...
                # Simple extraction logic based on column names starting with 'rank'
                rank_cols = sorted([k for k in row.keys() if k.startswith('rank')])
                
                for col in rank_cols:
                    candidate = row[col]
                    if candidate and candidate.strip():
                        # BUG 1: Case sensitivity.
                        # Should be candidate.strip().title() or similar normalization.
                        ranked_candidates.append(candidate.strip())
                
                if ranked_candidates:
                    ballots.append(ranked_candidates)
    except FileNotFoundError:
        print(f"Error: File {filepath} not found.")
        return []
        
    return ballots
EOF

# --- tally/engine.py (Buggy) ---
cat > "$PROJECT_DIR/tally/engine.py" << 'EOF'
"""
Core RCV Tallying Engine.
"""
from typing import List, Dict, Set, Optional
from collections import Counter

class RCVEngine:
    def __init__(self, ballots: List[List[str]]):
        self.ballots = ballots
        self.candidates = self._get_all_candidates()
        self.eliminated: Set[str] = set()
        self.rounds_log = []

    def _get_all_candidates(self) -> Set[str]:
        candidates = set()
        for ballot in self.ballots:
            for cand in ballot:
                candidates.add(cand)
        return candidates

    def run_election(self) -> str:
        """Run rounds until a winner is found."""
        total_initial_ballots = len(self.ballots)
        
        while True:
            # 1. Count votes for top active candidates
            counts = Counter()
            active_ballots_count = 0
            
            for ballot in self.ballots:
                top_choice = self._get_top_choice(ballot)
                if top_choice:
                    counts[top_choice] += 1
                    active_ballots_count += 1
            
            # Log round
            self.rounds_log.append(counts.copy())
            
            # Check if no candidates left (edge case)
            if not counts:
                return "No Winner"

            leading_candidate, leading_votes = counts.most_common(1)[0]
            
            # BUG 2: Majority Threshold Calculation.
            # RCV standard: Majority is > 50% of ACTIVE ballots.
            # Buggy: Majority is > 50% of TOTAL INITIAL ballots.
            # If many ballots are exhausted, a candidate might have 100% of active votes 
            # but less than 50% of initial votes, causing an infinite loop or wrong elimination.
            threshold = total_initial_ballots / 2
            
            if leading_votes > threshold:
                return leading_candidate
                
            # Tie breaking / Elimination
            # Find min votes
            min_votes = min(counts.values())
            candidates_with_min = [c for c, v in counts.items() if v == min_votes]
            
            # Eliminate the last one (simple tie break for this exercise: alphabetical)
            to_eliminate = sorted(candidates_with_min)[-1]
            self.eliminated.add(to_eliminate)
            
            # If only one candidate remains, they win
            remaining_candidates = self.candidates - self.eliminated
            if len(remaining_candidates) <= 1:
                return list(remaining_candidates)[0] if remaining_candidates else "No Winner"

    def _get_top_choice(self, ballot: List[str]) -> Optional[str]:
        """
        Find the highest ranked candidate on the ballot who is NOT eliminated.
        """
        # BUG 3: Transfer Logic / Ballot Traversal
        # This implementation just grabs the first candidate not in eliminated set.
        # But wait, logic: "Find highest ranked candidate on ballot who is NOT eliminated."
        # The simple iteration below IS generally correct for finding the current top choice.
        # However, let's inject a subtle bug in how we interpret the ballot list order
        # or maybe the "next choice" logic is often separate in RCV implementations.
        #
        # Let's make the bug: "If the first choice is eliminated, pick the second choice
        # WITHOUT checking if the second choice is ALSO eliminated."
        
        # Correct Logic:
        # for candidate in ballot:
        #    if candidate not in self.eliminated:
        #        return candidate
        # return None
        
        # Buggy Logic:
        # If top choice is eliminated, just return the next one in the list (if exists).
        # This fails if the next one is ALSO eliminated.
        
        if not ballot:
            return None
            
        current_top = ballot[0]
        
        if current_top not in self.eliminated:
            return current_top
            
        # If we are here, the 1st choice is eliminated.
        # We need to find the next valid choice.
        # BUG: The code assumes that if the 1st is eliminated, the 2nd is valid.
        # It doesn't loop recursively or iteratively enough to skip multiple eliminated candidates.
        
        if len(ballot) > 1:
            next_choice = ballot[1]
            # It returns the next choice even if that choice is also eliminated!
            # The calling function adds a vote to 'next_choice'. 
            # But 'next_choice' might be in self.eliminated.
            # If so, the vote goes to a ghost candidate or is discarded effectively depending on Counter.
            # If the Counter counts it, the while loop might try to eliminate them AGAIN or they just accumulate dead votes.
            return next_choice
            
        return None
EOF

# --- main.py ---
cat > "$PROJECT_DIR/main.py" << 'EOF'
from tally.loader import load_ballots
from tally.engine import RCVEngine

def main():
    print("Loading ballots...")
    ballots = load_ballots("data/election_2024.csv")
    print(f"Loaded {len(ballots)} ballots.")
    
    engine = RCVEngine(ballots)
    winner = engine.run_election()
    
    print(f"The winner is: {winner}")
    print("Rounds history:")
    for i, round_counts in enumerate(engine.rounds_log):
        print(f"Round {i+1}: {dict(round_counts)}")

if __name__ == "__main__":
    main()
EOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import sys
import os

# Add project root to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
EOF

# --- tests/test_loader.py ---
cat > "$PROJECT_DIR/tests/test_loader.py" << 'EOF'
import pytest
import csv
import os
from tally.loader import load_ballots

@pytest.fixture
def sample_csv(tmp_path):
    f = tmp_path / "ballots.csv"
    f.write_text("id,rank1,rank2\n1,Alice,Bob\n2,alice,Charlie\n3,BOB,alice")
    return str(f)

def test_load_ballots_structure(sample_csv):
    ballots = load_ballots(sample_csv)
    assert len(ballots) == 3
    assert isinstance(ballots[0], list)

def test_normalization(sample_csv):
    """Bug 1: Names should be normalized to Title Case."""
    ballots = load_ballots(sample_csv)
    # Check 2nd ballot, 1st choice 'alice' -> 'Alice'
    assert ballots[1][0] == "Alice", "Name 'alice' was not normalized to 'Alice'"
    # Check 3rd ballot, 1st choice 'BOB' -> 'Bob'
    assert ballots[2][0] == "Bob", "Name 'BOB' was not normalized to 'Bob'"

def test_empty_file(tmp_path):
    f = tmp_path / "empty.csv"
    f.write_text("id,rank1,rank2\n")
    ballots = load_ballots(str(f))
    assert ballots == []

def test_missing_file():
    ballots = load_ballots("non_existent.csv")
    assert ballots == []
EOF

# --- tests/test_engine.py ---
cat > "$PROJECT_DIR/tests/test_engine.py" << 'EOF'
import pytest
from tally.engine import RCVEngine

# Helper to normalize for the test input since we test Engine directly
def make_engine(ballots):
    return RCVEngine(ballots)

def test_simple_winner():
    # Alice has 3/5 votes (60%) - should win round 1
    ballots = [
        ['Alice', 'Bob'],
        ['Alice', 'Bob'],
        ['Alice', 'Bob'],
        ['Bob', 'Alice'],
        ['Bob', 'Alice']
    ]
    engine = make_engine(ballots)
    winner = engine.run_election()
    assert winner == 'Alice'

def test_transfer_logic_skips_eliminated():
    """Bug 2: Transfers should skip ALL eliminated candidates."""
    # Round 1:
    # Alice: 2
    # Bob: 2
    # Dave: 1 (Eliminated first)
    #
    # Dave's ballot is ['Dave', 'Eve', 'Alice']
    # If Eve is already eliminated (let's force a scenario where we verify the skip logic directly).
    #
    # Let's verify _get_top_choice logic directly.
    
    engine = RCVEngine([])
    engine.eliminated = {'Dave', 'Eve'}
    
    # Ballot: Dave -> Eve -> Alice
    ballot = ['Dave', 'Eve', 'Alice']
    
    # Should return Alice, because Dave and Eve are eliminated
    top = engine._get_top_choice(ballot)
    assert top == 'Alice', f"Should skip Dave and Eve to find Alice, but got {top}"

def test_majority_excludes_exhausted():
    """Bug 3: Majority threshold should be based on ACTIVE ballots."""
    # Scenario: 5 ballots.
    # 2 ballots: Alice
    # 3 ballots: Exhausted (empty or all eliminated) - effectively 0 active votes for them?
    # Actually, let's model exhausted by having candidates who are eliminated and no backups.
    
    # 1. Alice
    # 2. Alice
    # 3. Bob (Eliminated)
    # 4. Bob (Eliminated)
    # 5. Bob (Eliminated)
    
    # If Bob is eliminated, ballots 3,4,5 are exhausted (no next choice).
    # Remaining active ballots: 2 (for Alice).
    # Alice has 2 votes. Active ballots = 2. Alice has 100% of active.
    # If threshold uses total (5), threshold is 2.5. Alice (2) < 2.5. Alice doesn't win.
    # Infinite loop or wrong behavior.
    
    ballots = [
        ['Alice'],
        ['Alice'],
        ['Bob'],
        ['Bob'],
        ['Bob']
    ]
    engine = make_engine(ballots)
    
    # Force eliminate Bob to simulate the state
    engine.eliminated.add('Bob')
    
    # Check run
    # Alice should win immediately because she has 2/2 active votes.
    winner = engine.run_election()
    assert winner == 'Alice'

def test_transfer_vote():
    # Standard IRV scenario
    # A: 2, B: 2, C: 1. C eliminated. C->A. A wins 3 vs 2.
    ballots = [
        ['A', 'B'],
        ['A', 'B'],
        ['B', 'A'],
        ['B', 'A'],
        ['C', 'A']
    ]
    engine = make_engine(ballots)
    winner = engine.run_election()
    assert winner == 'A'

def test_tie_breaking_alphabetical():
    # A: 1, B: 1. Tie. B eliminated (alphabetically later? No, min votes).
    # Code eliminates sorted(candidates)[-1].
    # candidates with min votes: A (1), B (1).
    # sorted: ['A', 'B']. -1 is B. B eliminated. A wins.
    ballots = [
        ['A'],
        ['B']
    ]
    engine = make_engine(ballots)
    winner = engine.run_election()
    assert winner == 'A'

def test_deep_chain_elimination():
    # C1 -> C2 -> C3 -> Winner
    # C1, C2, C3 eliminated.
    engine = RCVEngine([])
    engine.eliminated = {'C1', 'C2', 'C3'}
    ballot = ['C1', 'C2', 'C3', 'Winner']
    assert engine._get_top_choice(ballot) == 'Winner'

def test_all_exhausted():
    ballots = [['A'], ['B']]
    engine = make_engine(ballots)
    engine.eliminated = {'A', 'B'}
    # Run election might return "No Winner"
    # Overriding eliminated for test setup isn't enough for run_election logic flow,
    # but let's see if it handles no winner gracefully.
    assert engine.run_election() is not None # Just shouldn't crash
EOF

# --- PyCharm Setup ---
source /workspace/scripts/task_utils.sh

# Open PyCharm with the project
setup_pycharm_project "$PROJECT_DIR" "rcv_tally"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "Setup complete."