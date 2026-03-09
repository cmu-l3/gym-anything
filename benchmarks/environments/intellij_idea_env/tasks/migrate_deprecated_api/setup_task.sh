#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up migrate_deprecated_api task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/IdeaProjects/data-pipeline"

# Clean previous attempts
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/pipeline"
mkdir -p "$PROJECT_DIR/src/test/java/com/pipeline"

# --- pom.xml ---
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                             http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.pipeline</groupId>
    <artifactId>data-pipeline</artifactId>
    <version>2.4.0</version>
    <packaging>jar</packaging>
    <name>data-pipeline</name>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>
    <dependencies>
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.12</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# --- DataProcessor.java (the class with both methods) ---
cat > "$PROJECT_DIR/src/main/java/com/pipeline/DataProcessor.java" << 'JAVAEOF'
package com.pipeline;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;

/**
 * Core data processing engine.
 */
public class DataProcessor {

    private final int batchSize;
    private final boolean deduplication;

    public DataProcessor(int batchSize, boolean deduplication) {
        this.batchSize = batchSize;
        this.deduplication = deduplication;
    }

    public DataProcessor() {
        this(1000, true);
    }

    /**
     * Process a list of string data records.
     *
     * @deprecated since 2.4.0, use {@link #processModern(List)} instead.
     */
    @Deprecated
    public List<String> processLegacy(List<String> input) {
        if (input == null || input.isEmpty()) {
            return Collections.emptyList();
        }
        List<String> result = new ArrayList<>();
        for (String item : input) {
            if (item != null && !item.isBlank()) {
                String transformed = item.trim().toUpperCase();
                if (!deduplication || !result.contains(transformed)) {
                    result.add(transformed);
                }
            }
        }
        if (result.size() > batchSize) {
            return result.subList(0, batchSize);
        }
        return Collections.unmodifiableList(result);
    }

    /**
     * Modern replacement for {@link #processLegacy(List)}.
     */
    public List<String> processModern(List<String> input) {
        if (input == null || input.isEmpty()) {
            return Collections.emptyList();
        }
        var stream = input.stream()
                .filter(s -> s != null && !s.isBlank())
                .map(s -> s.trim().toUpperCase());

        if (deduplication) {
            stream = stream.distinct();
        }

        return stream.limit(batchSize).collect(Collectors.toUnmodifiableList());
    }
}
JAVAEOF

# --- BatchRunner.java (3 calls) ---
cat > "$PROJECT_DIR/src/main/java/com/pipeline/BatchRunner.java" << 'JAVAEOF'
package com.pipeline;

import java.util.ArrayList;
import java.util.List;

public class BatchRunner {
    private final DataProcessor processor;

    public BatchRunner(DataProcessor processor) {
        this.processor = processor;
    }

    public List<String> runFullDataset(List<String> dataset) {
        List<String> allResults = new ArrayList<>();
        // Call 1
        List<String> firstPass = processor.processLegacy(dataset);
        allResults.addAll(firstPass);

        List<String> deferred = dataset.stream()
                .filter(s -> s != null && s.startsWith("DEFER:"))
                .map(s -> s.substring(6))
                .toList();

        if (!deferred.isEmpty()) {
            // Call 2
            List<String> secondPass = processor.processLegacy(deferred);
            allResults.addAll(secondPass);
        }
        return allResults;
    }

    public List<String> runSingleBatch(List<String> smallDataset) {
        // Call 3
        return processor.processLegacy(smallDataset);
    }
}
JAVAEOF

# --- StreamHandler.java (2 calls) ---
cat > "$PROJECT_DIR/src/main/java/com/pipeline/StreamHandler.java" << 'JAVAEOF'
package com.pipeline;

import java.util.ArrayList;
import java.util.List;

public class StreamHandler {
    private final DataProcessor processor;
    private final List<String> buffer;
    private final int flushThreshold;

    public StreamHandler(DataProcessor processor, int flushThreshold) {
        this.processor = processor;
        this.buffer = new ArrayList<>();
        this.flushThreshold = flushThreshold;
    }

    public List<String> ingest(String record) {
        buffer.add(record);
        if (buffer.size() >= flushThreshold) {
            return flush();
        }
        return List.of();
    }

    public List<String> flush() {
        if (buffer.isEmpty()) return List.of();
        List<String> snapshot = new ArrayList<>(buffer);
        buffer.clear();
        // Call 1
        List<String> processed = processor.processLegacy(snapshot);

        if (processed.size() < snapshot.size() / 2) {
            // Call 2
            return processor.processLegacy(snapshot);
        }
        return processed;
    }
}
JAVAEOF

# --- ReportGenerator.java (2 calls) ---
cat > "$PROJECT_DIR/src/main/java/com/pipeline/ReportGenerator.java" << 'JAVAEOF'
package com.pipeline;
import java.util.List;
import java.util.StringJoiner;

public class ReportGenerator {
    private final DataProcessor processor;
    public ReportGenerator(DataProcessor processor) { this.processor = processor; }

    public String generateSummary(List<String> rawData) {
        // Call 1
        List<String> processed = processor.processLegacy(rawData);
        return "Processed: " + processed.size();
    }

    public String generateCsv(List<String> rawData) {
        // Call 2
        List<String> processed = processor.processLegacy(rawData);
        StringJoiner sj = new StringJoiner(",");
        processed.forEach(sj::add);
        return sj.toString();
    }
}
JAVAEOF

# --- CacheManager.java (2 calls) ---
cat > "$PROJECT_DIR/src/main/java/com/pipeline/CacheManager.java" << 'JAVAEOF'
package com.pipeline;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class CacheManager {
    private final DataProcessor processor;
    private final Map<Integer, List<String>> cache = new HashMap<>();

    public CacheManager(DataProcessor processor) { this.processor = processor; }

    public List<String> processWithCache(List<String> data) {
        if (cache.containsKey(data.hashCode())) return cache.get(data.hashCode());
        // Call 1
        List<String> result = processor.processLegacy(data);
        cache.put(data.hashCode(), result);
        return result;
    }

    public List<String> forceProcess(List<String> data) {
        // Call 2
        return processor.processLegacy(data);
    }
}
JAVAEOF

# --- App.java (1 call) ---
cat > "$PROJECT_DIR/src/main/java/com/pipeline/App.java" << 'JAVAEOF'
package com.pipeline;
import java.util.Arrays;
import java.util.List;

public class App {
    public static void main(String[] args) {
        DataProcessor processor = new DataProcessor();
        List<String> data = Arrays.asList("hello", "world");
        // Call 1
        List<String> results = processor.processLegacy(data);
        results.forEach(System.out::println);
    }
}
JAVAEOF

# --- DataProcessorTest.java (2 calls) ---
cat > "$PROJECT_DIR/src/test/java/com/pipeline/DataProcessorTest.java" << 'JAVAEOF'
package com.pipeline;
import org.junit.Test;
import java.util.Arrays;
import java.util.List;
import static org.junit.Assert.*;

public class DataProcessorTest {
    @Test
    public void testLegacy() {
        DataProcessor p = new DataProcessor();
        // Call 1
        List<String> res = p.processLegacy(Arrays.asList("a", "b"));
        assertEquals(2, res.size());
    }

    @Test
    public void testEmpty() {
        // Call 2
        assertTrue(new DataProcessor().processLegacy(null).isEmpty());
    }
}
JAVAEOF

chown -R ga:ga "$PROJECT_DIR"

# Record initial file stats for anti-gaming
find "$PROJECT_DIR" -name "*.java" -exec stat -c "%n %Y" {} \; > /tmp/initial_file_stats.txt

# Open project
setup_intellij_project "$PROJECT_DIR" "data-pipeline" 120

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="