#!/bin/bash
echo "=== Setting up fix_raft_consensus task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_raft_consensus"
PROJECT_DIR="/home/ga/PycharmProjects/raft_kv"

# Clean up previous runs
rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json

# Create project structure
mkdir -p "$PROJECT_DIR/raft"
mkdir -p "$PROJECT_DIR/tests"

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'REQUIREMENTS'
pytest>=7.0
REQUIREMENTS

# --- raft/__init__.py ---
touch "$PROJECT_DIR/raft/__init__.py"

# --- raft/messages.py (Correct) ---
cat > "$PROJECT_DIR/raft/messages.py" << 'PYEOF'
from dataclasses import dataclass
from enum import Enum
from typing import Optional

class MessageType(Enum):
    REQUEST_VOTE = 1
    VOTE_RESPONSE = 2
    APPEND_ENTRIES = 3
    APPEND_RESPONSE = 4

@dataclass
class Message:
    term: int
    src_id: str
    dst_id: str
    type: MessageType
    
@dataclass
class RequestVote(Message):
    last_log_index: int
    last_log_term: int

@dataclass
class VoteResponse(Message):
    granted: bool

@dataclass
class AppendEntries(Message):
    prev_log_index: int
    prev_log_term: int
    entries: list
    leader_commit: int
PYEOF

# --- raft/consensus.py (Buggy) ---
cat > "$PROJECT_DIR/raft/consensus.py" << 'PYEOF'
import random
import time
import threading
from enum import Enum
from typing import List, Optional, Dict, Callable
from .messages import Message, MessageType, RequestVote, VoteResponse, AppendEntries

class NodeState(Enum):
    FOLLOWER = 1
    CANDIDATE = 2
    LEADER = 3

class RaftNode:
    def __init__(self, node_id: str, peers: List[str], send_func: Callable):
        self.node_id = node_id
        self.peers = peers
        self.send_func = send_func  # Function to send messages to network
        
        # Persistent state
        self.current_term = 0
        self.voted_for = None
        self.log = []
        
        # Volatile state
        self.state = NodeState.FOLLOWER
        self.commit_index = 0
        self.last_applied = 0
        
        # BUG 1: Election timeout is fixed constant (0.15s).
        # Raft requires randomized timeout (e.g. 0.15 to 0.30) to prevent split votes.
        self.election_timeout = 0.15
        
        self.last_heartbeat = time.time()
        self.votes_received = set()
        
    def get_timeout(self):
        """Return the current election timeout setting."""
        return self.election_timeout

    def handle_message(self, msg: Message):
        """Main event loop entry point."""
        if msg.term > self.current_term:
            self.current_term = msg.term
            self.state = NodeState.FOLLOWER
            self.voted_for = None
            
        if msg.type == MessageType.REQUEST_VOTE:
            self._handle_request_vote(msg)
        elif msg.type == MessageType.VOTE_RESPONSE:
            self._handle_vote_response(msg)
        elif msg.type == MessageType.APPEND_ENTRIES:
            self._handle_append_entries(msg)

    def _handle_request_vote(self, msg: RequestVote):
        """Handle incoming vote request."""
        # BUG 2: Safety violation.
        # Should return False immediately if msg.term < self.current_term.
        # The code falls through and might grant vote if voted_for is None.
        
        can_vote = (self.voted_for is None or self.voted_for == msg.src_id)
        
        if can_vote:
            self.voted_for = msg.src_id
            self.last_heartbeat = time.time() # Reset election timer
            response = VoteResponse(
                term=self.current_term,
                src_id=self.node_id,
                dst_id=msg.src_id,
                type=MessageType.VOTE_RESPONSE,
                granted=True
            )
        else:
            response = VoteResponse(
                term=self.current_term,
                src_id=self.node_id,
                dst_id=msg.src_id,
                type=MessageType.VOTE_RESPONSE,
                granted=False
            )
        self.send_func(response)

    def _handle_vote_response(self, msg: VoteResponse):
        if self.state == NodeState.CANDIDATE and msg.granted:
            self.votes_received.add(msg.src_id)
            if len(self.votes_received) > (len(self.peers) + 1) // 2:
                self._become_leader()

    def _handle_append_entries(self, msg: AppendEntries):
        """Handle heartbeat/log replication."""
        # BUG 3: Stale Leader problem.
        # If we receive a valid heartbeat from a leader with term >= current_term,
        # we MUST step down to FOLLOWER.
        # Current code checks term but doesn't update state if currently CANDIDATE.
        
        if msg.term >= self.current_term:
            self.current_term = msg.term
            self.last_heartbeat = time.time()
            # MISSING: self.state = NodeState.FOLLOWER
            # This causes Candidates to stay Candidates even after a Leader is established.
            pass
            
    def _become_candidate(self):
        self.state = NodeState.CANDIDATE
        self.current_term += 1
        self.voted_for = self.node_id
        self.votes_received = {self.node_id}
        self.last_heartbeat = time.time()
        
        # Broadcast RequestVote
        for peer in self.peers:
            msg = RequestVote(
                term=self.current_term,
                src_id=self.node_id,
                dst_id=peer,
                type=MessageType.REQUEST_VOTE,
                last_log_index=len(self.log),
                last_log_term=0 # Simplified
            )
            self.send_func(msg)
            
    def _become_leader(self):
        self.state = NodeState.LEADER
        # Send initial heartbeat
        self._send_heartbeat()
        
    def _send_heartbeat(self):
        if self.state != NodeState.LEADER:
            return
        for peer in self.peers:
            msg = AppendEntries(
                term=self.current_term,
                src_id=self.node_id,
                dst_id=peer,
                type=MessageType.APPEND_ENTRIES,
                prev_log_index=0,
                prev_log_term=0,
                entries=[],
                leader_commit=self.commit_index
            )
            self.send_func(msg)

    def tick(self):
        """Called periodically by the main loop."""
        if self.state != NodeState.LEADER:
            # Check for election timeout
            if time.time() - self.last_heartbeat > self.election_timeout:
                self._become_candidate()
        else:
            # Send heartbeats (simplified frequency)
            self._send_heartbeat()
PYEOF

# --- tests/test_election.py ---
cat > "$PROJECT_DIR/tests/test_election.py" << 'PYEOF'
import pytest
import time
import random
import threading
from queue import Queue
from raft.consensus import RaftNode, NodeState
from raft.messages import Message, MessageType, RequestVote, AppendEntries

# --- Helper for simulation ---
class Network:
    def __init__(self):
        self.queues = {}
        self.drop_rate = 0.0

    def register(self, node_id):
        self.queues[node_id] = Queue()

    def send(self, msg: Message):
        if random.random() < self.drop_rate:
            return
        if msg.dst_id in self.queues:
            # Add slight delay to simulate network
            time.sleep(0.001) 
            self.queues[msg.dst_id].put(msg)

    def get_msg(self, node_id):
        if not self.queues[node_id].empty():
            return self.queues[node_id].get()
        return None

def test_randomized_timeout():
    """Bug 1: Election timeout must be randomized to prevent split votes."""
    timeouts = set()
    for i in range(50):
        # We dummy out send_func
        node = RaftNode(f"n{i}", [], lambda m: None)
        timeouts.add(node.get_timeout())
    
    # If timeout is fixed constant 0.15, len(timeouts) will be 1
    # If randomized, it should be >> 1
    assert len(timeouts) > 1, "Election timeout is not randomized! All nodes have same timeout."

def test_safety_outdated_term():
    """Bug 2: RequestVote must reject outdated terms."""
    node = RaftNode("n1", ["n2"], lambda m: None)
    node.current_term = 10
    
    # Incoming vote request from term 5 (outdated)
    msg = RequestVote(
        term=5,
        src_id="n2",
        dst_id="n1",
        type=MessageType.REQUEST_VOTE,
        last_log_index=0,
        last_log_term=0
    )
    
    # Mock send_func to capture response
    responses = []
    node.send_func = lambda m: responses.append(m)
    
    node.handle_message(msg)
    
    assert len(responses) == 1
    resp = responses[0]
    assert resp.type == MessageType.VOTE_RESPONSE
    assert resp.granted is False, "Node granted vote to outdated term!"

def test_candidate_steps_down():
    """Bug 3: Candidate must step down to Follower on valid Heartbeat."""
    node = RaftNode("n1", ["n2"], lambda m: None)
    node.current_term = 10
    node.state = NodeState.CANDIDATE
    
    # Incoming Heartbeat from valid Leader of same term
    msg = AppendEntries(
        term=10,
        src_id="n2",
        dst_id="n1",
        type=MessageType.APPEND_ENTRIES,
        prev_log_index=0,
        prev_log_term=0,
        entries=[],
        leader_commit=0
    )
    
    node.handle_message(msg)
    
    assert node.state == NodeState.FOLLOWER, "Candidate did not step down to Follower on valid heartbeat"

def test_leader_election_stabilizes():
    """Integration Test: Cluster should elect exactly one leader."""
    network = Network()
    nodes = []
    node_ids = ["n1", "n2", "n3", "n4", "n5"]
    
    for nid in node_ids:
        network.register(nid)
        peers = [p for p in node_ids if p != nid]
        node = RaftNode(nid, peers, network.send)
        nodes.append(node)
        
    # Run simulation
    start_time = time.time()
    stop_event = threading.Event()
    
    def run_node(n):
        while not stop_event.is_set():
            msg = network.get_msg(n.node_id)
            if msg:
                n.handle_message(msg)
            n.tick()
            time.sleep(0.01) # Tick rate

    threads = [threading.Thread(target=run_node, args=(n,)) for n in nodes]
    for t in threads: t.start()
    
    # Wait for convergence (allow 3 seconds)
    time.sleep(3)
    stop_event.set()
    for t in threads: t.join()
    
    leaders = [n for n in nodes if n.state == NodeState.LEADER]
    assert len(leaders) == 1, f"Expected 1 leader, found {len(leaders)}"
    
    # Check terms are consistent
    max_term = max(n.current_term for n in nodes)
    assert leaders[0].current_term == max_term
PYEOF

# Give permissions
chown -R ga:ga "$PROJECT_DIR"

echo "=== Setup complete ==="