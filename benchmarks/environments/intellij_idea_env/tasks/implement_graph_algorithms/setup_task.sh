#!/bin/bash
set -e
echo "=== Setting up Graph Algorithms Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/graph-algorithms"
mkdir -p "$PROJECT_DIR/src/main/java/graph"
mkdir -p "$PROJECT_DIR/src/test/java/graph"
mkdir -p "$PROJECT_DIR/src/test/resources"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>graph-algorithms</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.13.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
POM

# 2. Create Graph Interfaces and Helper Classes
cat > "$PROJECT_DIR/src/main/java/graph/Graph.java" << 'JAVA'
package graph;

import java.util.*;

public interface Graph {
    // Returns all nodes in the graph
    Set<Integer> getNodes();
    
    // Returns neighbors of a given node
    List<Integer> getNeighbors(int node);
    
    // Returns number of nodes
    int size();
}
JAVA

cat > "$PROJECT_DIR/src/main/java/graph/SimpleGraph.java" << 'JAVA'
package graph;

import java.util.*;

public class SimpleGraph implements Graph {
    private final Map<Integer, List<Integer>> adjList = new HashMap<>();

    public void addEdge(int u, int v) {
        adjList.computeIfAbsent(u, k -> new ArrayList<>()).add(v);
        adjList.computeIfAbsent(v, k -> new ArrayList<>()).add(u);
    }

    public void addNode(int u) {
        adjList.computeIfAbsent(u, k -> new ArrayList<>());
    }

    @Override
    public Set<Integer> getNodes() {
        return adjList.keySet();
    }

    @Override
    public List<Integer> getNeighbors(int node) {
        return adjList.getOrDefault(node, Collections.emptyList());
    }

    @Override
    public int size() {
        return adjList.size();
    }
}
JAVA

cat > "$PROJECT_DIR/src/main/java/graph/WeightedGraph.java" << 'JAVA'
package graph;

import java.util.*;

public class WeightedGraph extends SimpleGraph {
    private final Map<String, Double> weights = new HashMap<>();

    public void addWeightedEdge(int u, int v, double weight) {
        super.addEdge(u, v);
        weights.put(u + "-" + v, weight);
        weights.put(v + "-" + u, weight);
    }

    public double getWeight(int u, int v) {
        return weights.getOrDefault(u + "-" + v, Double.POSITIVE_INFINITY);
    }
}
JAVA

# 3. Create the Stub File (The Task)
cat > "$PROJECT_DIR/src/main/java/graph/GraphAlgorithms.java" << 'JAVA'
package graph;

import java.util.*;

public class GraphAlgorithms {

    /**
     * Perform Breadth-First Search starting from source.
     * Visit neighbors in ascending order of their IDs.
     * @return List of visited nodes in order.
     */
    public static List<Integer> bfs(Graph g, int source) {
        throw new UnsupportedOperationException("TODO: Implement BFS");
    }

    /**
     * Perform Depth-First Search starting from source.
     * Tip: When pushing neighbors to stack, consider order to pop lowest ID first.
     * @return List of visited nodes in order.
     */
    public static List<Integer> dfs(Graph g, int source) {
        throw new UnsupportedOperationException("TODO: Implement DFS");
    }

    /**
     * Detect if the undirected graph contains a cycle.
     */
    public static boolean hasCycle(Graph g) {
        throw new UnsupportedOperationException("TODO: Implement Cycle Detection");
    }

    /**
     * Find all connected components in the graph.
     * @return A list of sets, where each set is a connected component.
     */
    public static List<Set<Integer>> connectedComponents(Graph g) {
        throw new UnsupportedOperationException("TODO: Implement Connected Components");
    }

    /**
     * Find the shortest path using Dijkstra's algorithm.
     */
    public static ShortestPathResult shortestPath(WeightedGraph g, int source, int target) {
        throw new UnsupportedOperationException("TODO: Implement Dijkstra");
    }

    // Helper record for Dijkstra results
    public record ShortestPathResult(List<Integer> path, double distance) {
        public static ShortestPathResult unreachable() {
            return new ShortestPathResult(Collections.emptyList(), Double.POSITIVE_INFINITY);
        }
    }
}
JAVA

# 4. Create Data Loader
cat > "$PROJECT_DIR/src/main/java/graph/GraphLoader.java" << 'JAVA'
package graph;

import java.io.*;
import java.util.*;

public class GraphLoader {
    public static SimpleGraph loadFromResource(String resourcePath) throws IOException {
        SimpleGraph g = new SimpleGraph();
        try (InputStream is = GraphLoader.class.getResourceAsStream(resourcePath);
             Scanner scanner = new Scanner(is)) {
            while (scanner.hasNextInt()) {
                int u = scanner.nextInt();
                int v = scanner.nextInt();
                g.addEdge(u, v);
            }
        }
        return g;
    }

    public static WeightedGraph loadWeightedFromResource(String resourcePath) throws IOException {
        WeightedGraph g = new WeightedGraph();
        try (InputStream is = GraphLoader.class.getResourceAsStream(resourcePath);
             Scanner scanner = new Scanner(is)) {
            while (scanner.hasNext()) {
                int u = scanner.nextInt();
                int v = scanner.nextInt();
                double w = scanner.nextDouble();
                g.addWeightedEdge(u, v, w);
            }
        }
        return g;
    }
}
JAVA

# 5. Create Tests
cat > "$PROJECT_DIR/src/test/java/graph/GraphAlgorithmsTest.java" << 'JAVA'
package graph;

import org.junit.BeforeClass;
import org.junit.Test;
import java.util.*;
import static org.junit.Assert.*;

public class GraphAlgorithmsTest {
    private static SimpleGraph karateGraph;
    private static WeightedGraph weightedGraph;

    @BeforeClass
    public static void setup() throws Exception {
        karateGraph = GraphLoader.loadFromResource("/karate_club.edges");
        weightedGraph = GraphLoader.loadWeightedFromResource("/small_weighted.edges");
    }

    // --- BFS TESTS ---
    @Test
    public void testBfsVisitOrder() {
        // BFS from node 0 in Karate graph (Node 0 connects to 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 17, 19, 21, 31)
        List<Integer> visit = GraphAlgorithms.bfs(karateGraph, 0);
        assertEquals("Should visit all 34 nodes", 34, visit.size());
        assertEquals("First node should be source", (Integer)0, visit.get(0));
        // Check immediate neighbors are visited early (indices 1-16)
        Set<Integer> firstLayer = new HashSet<>(visit.subList(1, 17));
        assertTrue(firstLayer.contains(1));
        assertTrue(firstLayer.contains(31));
    }

    @Test
    public void testBfsReachesAllNodes() {
        SimpleGraph line = new SimpleGraph();
        line.addEdge(1, 2); line.addEdge(2, 3);
        List<Integer> visit = GraphAlgorithms.bfs(line, 1);
        assertEquals(Arrays.asList(1, 2, 3), visit);
    }

    @Test
    public void testBfsFromIsolatedNode() {
        SimpleGraph iso = new SimpleGraph();
        iso.addNode(5);
        assertEquals(Collections.singletonList(5), GraphAlgorithms.bfs(iso, 5));
    }

    // --- DFS TESTS ---
    @Test
    public void testDfsVisitOrder() {
        List<Integer> visit = GraphAlgorithms.dfs(karateGraph, 33);
        assertEquals("Should visit all 34 nodes", 34, visit.size());
        assertEquals("First node should be source", (Integer)33, visit.get(0));
    }

    @Test
    public void testDfsReachesAllNodes() {
        SimpleGraph tri = new SimpleGraph();
        tri.addEdge(0, 1); tri.addEdge(1, 2); tri.addEdge(2, 0);
        List<Integer> visit = GraphAlgorithms.dfs(tri, 0);
        assertEquals(3, visit.size());
    }

    @Test
    public void testDfsFromIsolatedNode() {
        SimpleGraph iso = new SimpleGraph();
        iso.addNode(99);
        assertEquals(Collections.singletonList(99), GraphAlgorithms.dfs(iso, 99));
    }

    // --- DIJKSTRA TESTS ---
    @Test
    public void testDijkstraDirectPath() {
        // 0 -> 1 (weight 2.0)
        var result = GraphAlgorithms.shortestPath(weightedGraph, 0, 1);
        assertEquals(2.0, result.distance(), 0.001);
        assertEquals(Arrays.asList(0, 1), result.path());
    }

    @Test
    public void testDijkstraLongerPath() {
        // 0 -> 1 -> 3 (2.0 + 5.0 = 7.0) vs 0 -> 2 -> 3 (4.0 + 1.0 = 5.0)
        // Should choose 0->2->3
        var result = GraphAlgorithms.shortestPath(weightedGraph, 0, 3);
        assertEquals(5.0, result.distance(), 0.001);
        assertEquals(Arrays.asList(0, 2, 3), result.path());
    }

    @Test
    public void testDijkstraSameNode() {
        var result = GraphAlgorithms.shortestPath(weightedGraph, 0, 0);
        assertEquals(0.0, result.distance(), 0.001);
        assertEquals(Collections.singletonList(0), result.path());
    }

    @Test
    public void testDijkstraUnreachable() {
        WeightedGraph g = new WeightedGraph();
        g.addNode(0); g.addNode(1);
        var result = GraphAlgorithms.shortestPath(g, 0, 1);
        assertEquals(Double.POSITIVE_INFINITY, result.distance(), 0.001);
        assertTrue(result.path().isEmpty());
    }

    // --- CYCLE TESTS ---
    @Test
    public void testHasCycleTrue() {
        assertTrue("Karate graph has many cycles", GraphAlgorithms.hasCycle(karateGraph));
    }

    @Test
    public void testHasCycleFalse() {
        SimpleGraph tree = new SimpleGraph();
        tree.addEdge(1, 2); tree.addEdge(1, 3); tree.addEdge(3, 4);
        assertFalse("Tree should not have cycle", GraphAlgorithms.hasCycle(tree));
    }

    @Test
    public void testHasCycleSingleNode() {
        SimpleGraph single = new SimpleGraph();
        single.addNode(1);
        assertFalse(GraphAlgorithms.hasCycle(single));
    }

    // --- COMPONENT TESTS ---
    @Test
    public void testConnectedComponentsKarate() {
        List<Set<Integer>> comps = GraphAlgorithms.connectedComponents(karateGraph);
        assertEquals(1, comps.size());
        assertEquals(34, comps.get(0).size());
    }

    @Test
    public void testConnectedComponentsDisconnected() {
        SimpleGraph g = new SimpleGraph();
        g.addEdge(1, 2); // C1
        g.addEdge(3, 4); g.addEdge(4, 5); // C2
        g.addNode(6); // C3
        
        List<Set<Integer>> comps = GraphAlgorithms.connectedComponents(g);
        assertEquals(3, comps.size());
        
        // Check sizes
        List<Integer> sizes = new ArrayList<>();
        for (Set<Integer> c : comps) sizes.add(c.size());
        Collections.sort(sizes);
        assertEquals(Arrays.asList(1, 2, 3), sizes);
    }

    @Test
    public void testConnectedComponentsSingletons() {
        SimpleGraph g = new SimpleGraph();
        g.addNode(1); g.addNode(2);
        assertEquals(2, GraphAlgorithms.connectedComponents(g).size());
    }
}
JAVA

# 6. Create Data Files
# Zachary's Karate Club (Subset of edges for brevity, but structurally representative)
# Real file would have 78 edges. We'll generate the full set here.
cat > "$PROJECT_DIR/src/test/resources/karate_club.edges" << 'EDGES'
0 1
0 2
0 3
0 4
0 5
0 6
0 7
0 8
0 10
0 11
0 12
0 13
0 17
0 19
0 21
0 31
1 2
1 3
1 7
1 13
1 17
1 19
1 21
1 30
2 3
2 7
2 8
2 9
2 13
2 27
2 28
2 32
3 7
3 12
3 13
4 6
4 10
5 6
5 10
5 16
6 16
8 30
8 32
8 33
9 33
13 33
14 32
14 33
15 32
15 33
18 32
18 33
19 33
20 32
20 33
22 32
22 33
23 25
23 27
23 29
23 32
23 33
24 25
24 27
24 31
25 31
26 29
26 33
27 33
28 31
28 33
29 32
29 33
30 32
30 33
31 32
31 33
32 33
EDGES

# Weighted Graph for Dijkstra
# 0 --(2)--> 1 --(5)--> 3
# |          ^
# (4)        | (1)
# v          |
# 2 --(1)--> 3
# 2 --(3)--> 4
# 4 --(1)--> 5
cat > "$PROJECT_DIR/src/test/resources/small_weighted.edges" << 'EDGES'
0 1 2.0
0 2 4.0
1 3 5.0
2 3 1.0
2 4 3.0
3 1 1.0
4 5 1.0
3 5 10.0
5 0 8.0
EDGES

# 7. Set permissions and hash
chown -R ga:ga "$PROJECT_DIR"
md5sum "$PROJECT_DIR/src/main/java/graph/GraphAlgorithms.java" > /tmp/stub_hash.txt

# 8. Pre-warm Maven (download dependencies)
echo "Pre-warming Maven..."
su - ga -c "cd $PROJECT_DIR && mvn clean compile > /dev/null 2>&1"

# 9. Record task start
date +%s > /tmp/task_start_time.txt

# 10. Open IntelliJ
echo "Launching IntelliJ..."
setup_intellij_project "$PROJECT_DIR" "graph-algorithms" 120

# 11. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="