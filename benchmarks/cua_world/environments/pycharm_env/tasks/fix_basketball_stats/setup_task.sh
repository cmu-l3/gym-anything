#!/bin/bash
set -e
echo "=== Setting up fix_basketball_stats task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/league_builder"
TASK_START_FILE="/tmp/fix_basketball_stats_start_ts"

# Clean previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/fix_basketball_stats_result.json
echo "$(date +%s)" > "$TASK_START_FILE"

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/league $PROJECT_DIR/tests $PROJECT_DIR/data"

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'REQUIREMENTS'
pytest>=7.0
numpy>=1.24.0
REQUIREMENTS

# --- league/__init__.py ---
touch "$PROJECT_DIR/league/__init__.py"

# --- league/models.py ---
cat > "$PROJECT_DIR/league/models.py" << 'PYEOF'
from dataclasses import dataclass, field
from typing import List, Dict

@dataclass
class Player:
    id: int
    name: str
    stats: Dict[str, int] = field(default_factory=lambda: {"points": 0, "assists": 0, "rebounds": 0})

@dataclass
class Team:
    id: str
    name: str
    wins: int = 0
    losses: int = 0
    point_diff: int = 0
    # List of (opponent_id, result_str 'W'/'L')
    match_history: List[tuple] = field(default_factory=list)

    @property
    def win_pct(self) -> float:
        total = self.wins + self.losses
        return self.wins / total if total > 0 else 0.0
PYEOF

# --- league/stats_engine.py (BUGGY) ---
cat > "$PROJECT_DIR/league/stats_engine.py" << 'PYEOF'
from typing import List, Dict
from league.models import Player, Team
import functools

class StatsEngine:
    
    def __init__(self):
        self.players = {}
        self.teams = {}

    def register_player(self, player_id: int, name: str):
        """Registers a new player with empty stats."""
        # BUG 1: Shared Mutable Default State
        # Defines a default dict once, assigns reference to all new players
        default_stats = {"points": 0, "assists": 0, "rebounds": 0}
        
        # When logic reuses this variable for multiple players without .copy(),
        # they point to the same object in memory.
        self.players[player_id] = Player(id=player_id, name=name, stats=default_stats)

    def update_player_stats(self, player_id: int, points: int, assists: int, rebounds: int):
        if player_id in self.players:
            p = self.players[player_id]
            p.stats["points"] += points
            p.stats["assists"] += assists
            p.stats["rebounds"] += rebounds

    def calculate_current_streak(self, team: Team) -> int:
        """Calculates the current winning streak."""
        streak = 0
        # match_history is chronological list of (opponent_id, 'W'/'L')
        for _, result in team.match_history:
            if result == 'W':
                streak += 1
            # BUG 3: Missing reset on loss
            # if result == 'L': streak = 0  <-- This logic is missing
            # The streak just pauses on a loss instead of resetting
        return streak

    def sort_standings(self, teams: List[Team]) -> List[Team]:
        """
        Sorts teams for playoffs.
        Primary: Wins (descending)
        Secondary: Head-to-Head (if 2 teams tied)
        Tertiary: Point Differential (descending)
        """
        # BUG 2: Tie-Breaker Logic Missing
        # Currently just sorts by Wins then Point Diff.
        # Ignores H2H.
        
        def simple_compare(t1, t2):
            # Sort by wins desc
            if t1.wins != t2.wins:
                return t2.wins - t1.wins
            
            # Skip H2H logic...
            
            # Sort by point diff desc
            return t2.point_diff - t1.point_diff

        return sorted(teams, key=functools.cmp_to_key(simple_compare))

    def _get_head_to_head_winner(self, team_a: Team, team_b: Team) -> int:
        """Helper: returns 1 if A beat B more, -1 if B beat A more, 0 if tie."""
        a_wins = 0
        b_wins = 0
        for opp_id, res in team_a.match_history:
            if opp_id == team_b.id:
                if res == 'W': a_wins += 1
                else: b_wins += 1
        
        if a_wins > b_wins: return 1
        if b_wins > a_wins: return -1
        return 0
PYEOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
from league.stats_engine import StatsEngine
from league.models import Team

@pytest.fixture
def engine():
    return StatsEngine()

@pytest.fixture
def sample_teams():
    t1 = Team("T1", "Hawks")
    t2 = Team("T2", "Eagles")
    t3 = Team("T3", "Falcons")
    return [t1, t2, t3]
PYEOF

# --- tests/test_player_aggregation.py ---
cat > "$PROJECT_DIR/tests/test_player_aggregation.py" << 'PYEOF'
import pytest
from league.stats_engine import StatsEngine

def test_player_stats_isolation(engine):
    """
    Test that updating one player's stats does not affect another.
    Regression test for Bug 1 (Shared Mutable Default).
    """
    engine.register_player(1, "Alice")
    engine.register_player(2, "Bob")

    # Update Alice
    engine.update_player_stats(1, points=10, assists=5, rebounds=2)

    alice = engine.players[1]
    bob = engine.players[2]

    assert alice.stats["points"] == 10
    
    # Bob should still be 0. If shared state bug exists, Bob will have 10.
    assert bob.stats["points"] == 0, "Bob's stats corrupted by Alice's update! (Shared State Bug)"
    assert bob.stats["assists"] == 0

def test_player_stats_accumulation(engine):
    """Happy path test."""
    engine.register_player(1, "Alice")
    engine.update_player_stats(1, 10, 0, 0)
    engine.update_player_stats(1, 5, 0, 0)
    assert engine.players[1].stats["points"] == 15
PYEOF

# --- tests/test_standings.py ---
cat > "$PROJECT_DIR/tests/test_standings.py" << 'PYEOF'
import pytest
from league.models import Team
from league.stats_engine import StatsEngine

def test_standings_simple_wins(engine):
    """Test basic sorting by wins."""
    t1 = Team("T1", "A", wins=10)
    t2 = Team("T2", "B", wins=5)
    sorted_teams = engine.sort_standings([t2, t1])
    assert sorted_teams[0].id == "T1"

def test_standings_head_to_head_tiebreaker(engine):
    """
    Test that Head-to-Head record breaks ties before Point Differential.
    
    Scenario:
    Team A: 10 Wins, +50 Diff. Played Team B once and WON.
    Team B: 10 Wins, +100 Diff. Played Team A once and LOST.
    
    Correct Rank: Team A (due to H2H win), despite lower Point Diff.
    Buggy Rank: Team B (due to higher Point Diff).
    """
    # A beat B
    team_a = Team("A", "Team A", wins=10, point_diff=50)
    team_a.match_history.append(("B", "W"))
    
    # B lost to A
    team_b = Team("B", "Team B", wins=10, point_diff=100)
    team_b.match_history.append(("A", "L"))
    
    sorted_teams = engine.sort_standings([team_a, team_b])
    
    # Should be A then B
    assert sorted_teams[0].id == "A", "Head-to-Head logic failed! Team A beat Team B but is ranked lower."
    assert sorted_teams[1].id == "B"

def test_standings_circular_tie_fallback(engine):
    """
    Edge case: Circular tie (A beats B, B beats C, C beats A).
    Should fall back to Point Diff.
    """
    # All 10 wins
    a = Team("A", "A", wins=10, point_diff=10)
    b = Team("B", "B", wins=10, point_diff=20)
    c = Team("C", "C", wins=10, point_diff=30)
    
    # Circular history
    a.match_history.append(("B", "W")) # A > B
    b.match_history.append(("C", "W")) # B > C
    c.match_history.append(("A", "W")) # C > A
    
    sorted_teams = engine.sort_standings([a, b, c])
    
    # Since H2H is circular/equal, fall back to Point Diff
    # Order should be C (30), B (20), A (10)
    assert sorted_teams[0].id == "C"
    assert sorted_teams[1].id == "B"
    assert sorted_teams[2].id == "A"
PYEOF

# --- tests/test_streaks.py ---
cat > "$PROJECT_DIR/tests/test_streaks.py" << 'PYEOF'
import pytest
from league.models import Team
from league.stats_engine import StatsEngine

def test_streak_calculation_simple(engine):
    t = Team("T1", "T1")
    t.match_history = [("O1", "W"), ("O2", "W")]
    assert engine.calculate_current_streak(t) == 2

def test_streak_calculation_reset_on_loss(engine):
    """
    Test that streak resets to 0 after a loss.
    Sequence: W, W, L, W
    Current Streak should be 1.
    Buggy behavior: 3 (sums all Ws).
    """
    t = Team("T1", "T1")
    t.match_history = [
        ("O1", "W"),
        ("O2", "W"),
        ("O3", "L"), # Should reset here
        ("O4", "W")  # Streak starts again here
    ]
    
    streak = engine.calculate_current_streak(t)
    assert streak == 1, f"Streak calculation incorrect. Expected 1, got {streak}"

def test_streak_calculation_ending_loss(engine):
    t = Team("T1", "T1")
    t.match_history = [("O1", "W"), ("O2", "L")]
    assert engine.calculate_current_streak(t) == 0
PYEOF

# Launch PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_output.log 2>&1 &"

# Wait for PyCharm
wait_for_pycharm 120

# Handle Trust Project dialog if it appears
handle_trust_dialog 5

# Focus and maximize
focus_pycharm_window
sleep 2

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="