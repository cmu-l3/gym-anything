#!/bin/bash
set -e
echo "=== Setting up implement_network_analysis task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/citation_network"

# Clean previous state
rm -rf "$PROJECT_DIR"
rm -f /tmp/network_analysis_result.json /tmp/network_analysis_start_ts /tmp/initial_checksums.txt

# Create directories
su - ga -c "mkdir -p $PROJECT_DIR/network $PROJECT_DIR/tests $PROJECT_DIR/data"

# ==============================================================================
# 1. CORE GRAPH CLASS (Already implemented)
# ==============================================================================
cat > "$PROJECT_DIR/network/graph.py" << 'PYEOF'
"""Core Graph data structure."""
from typing import Set, Dict, List, Any, Iterator

class Graph:
    """A simple directed graph implementation using adjacency lists."""

    def __init__(self, directed: bool = True):
        self._adj: Dict[Any, Set[Any]] = {}
        self._nodes: Set[Any] = set()
        self.directed = directed

    def add_node(self, node: Any) -> None:
        """Add a node to the graph."""
        if node not in self._nodes:
            self._nodes.add(node)
            if node not in self._adj:
                self._adj[node] = set()

    def add_edge(self, u: Any, v: Any) -> None:
        """Add an edge from u to v."""
        self.add_node(u)
        self.add_node(v)
        self._adj[u].add(v)
        if not self.directed:
            self._adj[v].add(u)

    def neighbors(self, node: Any) -> Set[Any]:
        """Return the set of neighbors for a node."""
        return self._adj.get(node, set())

    @property
    def nodes(self) -> Set[Any]:
        return self._nodes

    def __len__(self) -> int:
        return len(self._nodes)
PYEOF

# ==============================================================================
# 2. STUB FILES (Agent must implement these)
# ==============================================================================

# network/metrics.py
cat > "$PROJECT_DIR/network/metrics.py" << 'PYEOF'
"""Network analysis metrics."""
from typing import Dict, Any
from .graph import Graph

def pagerank(graph: Graph, damping: float = 0.85, max_iter: int = 100, tol: float = 1.0e-6) -> Dict[Any, float]:
    """
    Compute PageRank for nodes in the graph using power iteration.

    Args:
        graph: The graph object.
        damping: Damping factor (alpha).
        max_iter: Maximum number of iterations.
        tol: Tolerance for convergence (L1 norm of difference).

    Returns:
        Dictionary mapping nodes to their PageRank values.
        Values should sum to 1.0.
        Handle dangling nodes (no outgoing edges) by treating them as connected to all nodes.
    """
    # TODO: Implement PageRank
    raise NotImplementedError("PageRank not implemented")


def betweenness_centrality(graph: Graph) -> Dict[Any, float]:
    """
    Compute betweenness centrality for all nodes.
    
    Uses Brandes' algorithm (BFS based).
    
    Returns:
        Dictionary mapping nodes to betweenness scores.
        Scores should be normalized by (n-1)(n-2) for directed graphs,
        or (n-1)(n-2)/2 for undirected graphs.
    """
    # TODO: Implement Betweenness Centrality
    raise NotImplementedError("Betweenness centrality not implemented")


def clustering_coefficient(graph: Graph, node: Any = None) -> float:
    """
    Compute the clustering coefficient.
    
    If node is provided:
        Compute local clustering coefficient: 2 * triangle_count / (deg * (deg - 1))
        (For directed graphs, consider total degree or neighbors ignoring direction)
    If node is None:
        Compute global average clustering coefficient.
        
    Returns:
        Float value between 0.0 and 1.0.
    """
    # TODO: Implement Clustering Coefficient
    raise NotImplementedError("Clustering coefficient not implemented")
PYEOF

# network/community.py
cat > "$PROJECT_DIR/network/community.py" << 'PYEOF'
"""Community detection algorithms."""
from typing import Dict, Any
from .graph import Graph

def label_propagation(graph: Graph, max_iter: int = 100) -> Dict[Any, int]:
    """
    Detect communities using synchronous label propagation.

    Algorithm:
    1. Initialize every node with a unique label (0 to n-1).
    2. In each iteration, update every node's label to the most frequent label 
       among its neighbors (break ties randomly or deterministically).
    3. Repeat until convergence or max_iter.

    Returns:
        Dictionary mapping node -> community_label (int).
    """
    # TODO: Implement Label Propagation
    raise NotImplementedError("Label propagation not implemented")
PYEOF

# network/io.py
cat > "$PROJECT_DIR/network/io.py" << 'PYEOF'
"""Input/Output utilities for graphs."""
from typing import Tuple, List, Any
from .graph import Graph

def read_edge_list(filepath: str, directed: bool = True) -> Graph:
    """
    Read a graph from an edge list file.
    
    Format:
    - Lines starting with '#' are comments.
    - Other lines contain two identifiers separated by whitespace (tab or space).
    - Source Target
    
    Args:
        filepath: Path to the file.
        directed: Whether the resulting graph is directed.
        
    Returns:
        A Graph object populated with nodes and edges.
    """
    # TODO: Implement read_edge_list
    raise NotImplementedError("read_edge_list not implemented")


def write_edge_list(graph: Graph, filepath: str) -> None:
    """
    Write a graph to an edge list file.
    
    Format:
    # Directed: True/False
    Source<TAB>Target
    ...
    
    Args:
        graph: The graph to write.
        filepath: Destination path.
    """
    # TODO: Implement write_edge_list
    raise NotImplementedError("write_edge_list not implemented")


def to_adjacency_matrix(graph: Graph) -> Tuple[List[List[int]], List[Any]]:
    """
    Convert graph to adjacency matrix representation.
    
    Returns:
        Tuple containing:
        1. List of lists (NxN matrix) where matrix[i][j] = 1 if edge i->j exists, else 0.
        2. List of nodes corresponding to the indices 0..N-1.
    """
    # TODO: Implement to_adjacency_matrix
    raise NotImplementedError("to_adjacency_matrix not implemented")
PYEOF

cat > "$PROJECT_DIR/network/__init__.py" << 'PYEOF'
"""Citation Network Analysis Library."""
PYEOF

# ==============================================================================
# 3. TEST FIXTURES
# ==============================================================================

cat > "$PROJECT_DIR/tests/__init__.py" << 'PYEOF'
PYEOF

cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
from network.graph import Graph

@pytest.fixture
def triangle_graph():
    """Complete graph of 3 nodes."""
    g = Graph(directed=True)
    g.add_edge("A", "B")
    g.add_edge("B", "C")
    g.add_edge("C", "A")
    # Make it fully connected for clustering test
    g.add_edge("B", "A")
    g.add_edge("C", "B")
    g.add_edge("A", "C")
    return g

@pytest.fixture
def star_graph():
    """Center 'C' connected to leaves L1-L4."""
    g = Graph(directed=True)
    for i in range(1, 5):
        g.add_edge(f"L{i}", "C") # pointing to center
    return g

@pytest.fixture
def path_graph():
    """A -> B -> C -> D"""
    g = Graph(directed=True)
    g.add_edge("A", "B")
    g.add_edge("B", "C")
    g.add_edge("C", "D")
    return g

@pytest.fixture
def barbell_graph():
    """Two cliques of 3 connected by a bridge."""
    # Clique 1: 1,2,3
    # Clique 2: 4,5,6
    # Bridge: 3-4
    g = Graph(directed=False)
    # Clique 1
    g.add_edge(1, 2); g.add_edge(2, 3); g.add_edge(3, 1)
    g.add_edge(2, 1); g.add_edge(3, 2); g.add_edge(1, 3)
    # Clique 2
    g.add_edge(4, 5); g.add_edge(5, 6); g.add_edge(6, 4)
    g.add_edge(5, 4); g.add_edge(6, 5); g.add_edge(4, 6)
    # Bridge
    g.add_edge(3, 4); g.add_edge(4, 3)
    return g
PYEOF

cat > "$PROJECT_DIR/tests/test_graph.py" << 'PYEOF'
from network.graph import Graph

def test_add_nodes_and_edges():
    g = Graph()
    g.add_edge(1, 2)
    assert 1 in g.nodes
    assert 2 in g.nodes
    assert 2 in g.neighbors(1)

def test_neighbors():
    g = Graph()
    g.add_edge("A", "B")
    g.add_edge("A", "C")
    assert g.neighbors("A") == {"B", "C"}
    assert g.neighbors("B") == set()

def test_node_count_edge_count():
    g = Graph()
    g.add_node(1)
    g.add_edge(1, 2)
    assert len(g) == 2

def test_is_directed():
    g = Graph(directed=True)
    assert g.directed is True
    g2 = Graph(directed=False)
    assert g2.directed is False
PYEOF

cat > "$PROJECT_DIR/tests/test_metrics.py" << 'PYEOF'
import pytest
import math
from network.metrics import pagerank, betweenness_centrality, clustering_coefficient

def test_pagerank_triangle(triangle_graph):
    pr = pagerank(triangle_graph)
    # Symmetry -> all equal
    assert pr["A"] == pytest.approx(1.0/3, abs=0.01)
    assert pr["B"] == pytest.approx(1.0/3, abs=0.01)
    assert pr["C"] == pytest.approx(1.0/3, abs=0.01)

def test_pagerank_star_center_highest(star_graph):
    pr = pagerank(star_graph)
    # Center should be highest
    values = list(pr.values())
    center_val = pr["C"]
    assert center_val > max(v for k, v in pr.items() if k != "C")

def test_pagerank_values_sum_to_one(path_graph):
    pr = pagerank(path_graph)
    assert sum(pr.values()) == pytest.approx(1.0, abs=0.001)

def test_betweenness_path_graph(path_graph):
    # A->B->C->D
    # Shortest paths:
    # A->B, A->B->C, A->B->C->D
    # B->C, B->C->D
    # C->D
    # B lies on: A->C, A->D. Count = 2.
    # C lies on: A->D, B->D. Count = 2.
    # Endpoints A, D = 0.
    bc = betweenness_centrality(path_graph)
    # Normalization factor for directed N=4: (4-1)(4-2) = 6
    assert bc["B"] == pytest.approx(2.0/6, abs=0.01)
    assert bc["C"] == pytest.approx(2.0/6, abs=0.01)
    assert bc["A"] == 0.0

def test_betweenness_star_center(star_graph):
    # 5 nodes (4 leaves + 1 center).
    # All paths from leaf to leaf must pass through center? 
    # Wait, star_graph fixture is L -> C. No path from L1 -> L2.
    # So betweenness is 0 for everyone if directed edges only go IN.
    # Let's check the fixture: L -> C. 
    # Ah, standard star usually implies undirected or bidirectional for centrality demos.
    # Let's treat it as is. If L1->C and L2->C, there is NO path L1->L2.
    # So BC should be 0 everywhere.
    bc = betweenness_centrality(star_graph)
    assert bc["C"] == 0.0
    
def test_betweenness_triangle_all_zero(triangle_graph):
    # Fully connected. Shortest path is always direct edge.
    # No node lies on shortest path between others.
    bc = betweenness_centrality(triangle_graph)
    assert bc["A"] == 0.0
    assert bc["B"] == 0.0

def test_clustering_triangle(triangle_graph):
    # Complete graph K3. CC should be 1.0.
    assert clustering_coefficient(triangle_graph, "A") == 1.0
    assert clustering_coefficient(triangle_graph) == 1.0

def test_clustering_star(star_graph):
    # No triangles in a star graph.
    assert clustering_coefficient(star_graph, "C") == 0.0
    assert clustering_coefficient(star_graph) == 0.0
PYEOF

cat > "$PROJECT_DIR/tests/test_community.py" << 'PYEOF'
from network.community import label_propagation
from network.graph import Graph

def test_label_propagation_disconnected():
    g = Graph(directed=False)
    g.add_edge(1, 2) # Component 1
    g.add_edge(3, 4) # Component 2
    
    comms = label_propagation(g)
    assert comms[1] == comms[2]
    assert comms[3] == comms[4]
    # Ideally different labels for disconnected parts, though technically LP *can* assign same label by chance if not seeded/constrained, but standard implementation converges to connected components for disconnected graph.
    # For safety, we just check internal consistency.

def test_label_propagation_two_cliques(barbell_graph):
    comms = label_propagation(barbell_graph)
    # Clique 1 members should have same label
    assert comms[1] == comms[2] == comms[3]
    # Clique 2 members should have same label
    assert comms[4] == comms[5] == comms[6]
    # Labels might differ between cliques
    # (Note: sometimes bridge nodes flip-flop, but for perfect cliques they usually stabilize)
    
def test_label_propagation_returns_all_nodes(barbell_graph):
    comms = label_propagation(barbell_graph)
    assert len(comms) == len(barbell_graph.nodes)
PYEOF

cat > "$PROJECT_DIR/tests/test_io.py" << 'PYEOF'
import os
import tempfile
from network.io import read_edge_list, write_edge_list, to_adjacency_matrix
from network.graph import Graph

def test_read_edge_list_from_snap_file():
    # Create dummy snap file
    content = "# NodeId NodeId\n1\t2\n2\t3\n# Comment\n3\t1"
    with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
        f.write(content)
        path = f.name
        
    try:
        g = read_edge_list(path, directed=True)
        assert len(g) == 3
        # Node IDs in file are strings usually unless parsed
        # Expecting implementation to handle them as strings or ints. 
        # Let's assume strings for generic parser, or cast to int if looks like int.
        # For this test, we accept either "1" or 1.
        nodes = list(g.nodes)
        if isinstance(nodes[0], int):
            assert 1 in g.nodes
            assert 2 in g.neighbors(1)
        else:
            assert "1" in g.nodes
            assert "2" in g.neighbors("1")
    finally:
        os.unlink(path)

def test_write_then_read_roundtrip():
    g = Graph()
    g.add_edge("X", "Y")
    g.add_edge("Y", "Z")
    
    with tempfile.NamedTemporaryFile(delete=False) as f:
        path = f.name
    
    try:
        write_edge_list(g, path)
        g2 = read_edge_list(path, directed=True)
        assert len(g2) == 3
        assert "Y" in g2.neighbors("X")
    finally:
        if os.path.exists(path):
            os.unlink(path)

def test_adjacency_matrix_triangle():
    g = Graph()
    g.add_edge(0, 1)
    g.add_edge(1, 0)
    g.add_edge(1, 2)
    
    mat, nodes = to_adjacency_matrix(g)
    assert len(mat) == 3
    assert len(mat[0]) == 3
    
    # Check mapping
    idx0 = nodes.index(0)
    idx1 = nodes.index(1)
    idx2 = nodes.index(2)
    
    assert mat[idx0][idx1] == 1
    assert mat[idx1][idx0] == 1
    assert mat[idx1][idx2] == 1
    assert mat[idx0][idx2] == 0

def test_adjacency_matrix_dimensions():
    g = Graph()
    g.add_node("A")
    mat, nodes = to_adjacency_matrix(g)
    assert len(mat) == 1
    assert mat[0][0] == 0
PYEOF

# ==============================================================================
# 4. SAMPLE DATA
# ==============================================================================
cat > "$PROJECT_DIR/data/cit_hepth_sample.txt" << 'DATAEOF'
# Directed graph (each unordered pair of nodes is saved once): Cit-HepTh.txt 
# High Energy Physics - Theory citation network
# Nodes: 27770 Edges: 352807
# FromNodeId	ToNodeId
1001	9304045
1001	9308122
1001	9309097
1001	9311042
1001	9401139
9304045	9308122
9304045	9309097
9308122	9309097
9308122	9311042
9308122	9401139
9309097	9304045
9309097	9401139
9311042	1001
9401139	1001
9401139	9304045
9401139	9308122
9501001	9401139
9501002	1001
9501002	9304045
DATAEOF

# ==============================================================================
# 5. SETUP CHECKS AND LAUNCH
# ==============================================================================

# Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'REQEOF'
pytest>=7.0
REQEOF

# Generate checksums to prevent test tampering
sha256sum "$PROJECT_DIR/tests/"*.py "$PROJECT_DIR/network/graph.py" > /tmp/initial_checksums.txt 2>/dev/null

# Record start time
date +%s > /tmp/network_analysis_start_ts

# Launch PyCharm
wait_for_pycharm 60 || echo "WARNING: PyCharm not ready"
setup_pycharm_project "$PROJECT_DIR" "citation_network" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="