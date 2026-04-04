#!/bin/bash
set -e

echo "=== Setting up fix_dependency_conflicts task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/data-pipeline"
mkdir -p "$PROJECT_DIR/src/main/java/com/pipeline/model"
mkdir -p "$PROJECT_DIR/src/test/java/com/pipeline"

# 1. Create pom.xml with CONFLICTS
# - jackson-core 2.9.0 pinned (too old for 2.15 features used)
# - commons-lang3 3.1 pinned (too old for truncate method used)
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.pipeline</groupId>
  <artifactId>data-pipeline</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <name>data-pipeline</name>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
  <dependencies>
    <!-- Jackson Databind 2.15.2 depends on Core 2.15.2 -->
    <dependency>
      <groupId>com.fasterxml.jackson.core</groupId>
      <artifactId>jackson-databind</artifactId>
      <version>2.15.2</version>
    </dependency>
    <!-- CONFLICT: This explicit declaration overrides the transitive 2.15.2 with 2.9.0 -->
    <!-- This will cause compilation failure on StreamWriteConstraints -->
    <dependency>
      <groupId>com.fasterxml.jackson.core</groupId>
      <artifactId>jackson-core</artifactId>
      <version>2.9.0</version>
    </dependency>

    <!-- CONFLICT: Version 3.1 does not have StringUtils.truncate (added in 3.5) -->
    <dependency>
      <groupId>org.apache.commons</groupId>
      <artifactId>commons-lang3</artifactId>
      <version>3.1</version>
    </dependency>
    
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.13.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
EOF

# 2. Create DataRecord.java (POJO)
cat > "$PROJECT_DIR/src/main/java/com/pipeline/model/DataRecord.java" << 'EOF'
package com.pipeline.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonIgnoreProperties(ignoreUnknown = true)
public class DataRecord {
    @JsonProperty("name")
    private String name;
    @JsonProperty("description")
    private String description;
    @JsonProperty("value")
    private double value;

    public DataRecord() {}
    public DataRecord(String name, String description, double value) {
        this.name = name;
        this.description = description;
        this.value = value;
    }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
    public double getValue() { return value; }
    public void setValue(double value) { this.value = value; }
}
EOF

# 3. Create DataFetcher.java (Uses Jackson 2.15+ StreamWriteConstraints)
cat > "$PROJECT_DIR/src/main/java/com/pipeline/DataFetcher.java" << 'EOF'
package com.pipeline;

import com.fasterxml.jackson.core.StreamWriteConstraints;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.pipeline.model.DataRecord;

public class DataFetcher {
    private final JsonMapper mapper;

    public DataFetcher() {
        // StreamWriteConstraints was introduced in Jackson 2.15
        // This will fail to compile if jackson-core is 2.9.0
        this.mapper = JsonMapper.builder()
            .streamWriteConstraints(
                StreamWriteConstraints.builder()
                    .maxNestingDepth(100)
                    .build())
            .build();
    }

    public DataRecord parseRecord(String json) throws Exception {
        return mapper.readValue(json, DataRecord.class);
    }
}
EOF

# 4. Create DataProcessor.java (Uses Commons Lang 3.5+ truncate)
cat > "$PROJECT_DIR/src/main/java/com/pipeline/DataProcessor.java" << 'EOF'
package com.pipeline;

import org.apache.commons.lang3.StringUtils;
import com.pipeline.model.DataRecord;

public class DataProcessor {
    public String summarize(DataRecord record) {
        // StringUtils.truncate was introduced in Commons Lang 3.5
        // This will fail to compile if commons-lang3 is 3.1
        String name = StringUtils.truncate(record.getName(), 50);
        String description = StringUtils.truncate(record.getDescription(), 200);
        return String.format("Record: %s - %s", name, description);
    }

    public boolean isValid(DataRecord record) {
        return StringUtils.isNotBlank(record.getName())
            && StringUtils.isNotBlank(record.getDescription());
    }
}
EOF

# 5. Create DataProcessorTest.java
cat > "$PROJECT_DIR/src/test/java/com/pipeline/DataProcessorTest.java" << 'EOF'
package com.pipeline;

import com.pipeline.model.DataRecord;
import org.junit.Test;
import static org.junit.Assert.*;

public class DataProcessorTest {
    @Test
    public void testSummarize() {
        DataProcessor processor = new DataProcessor();
        DataRecord record = new DataRecord("Test Record", "A description", 42.0);
        String summary = processor.summarize(record);
        assertNotNull(summary);
        assertTrue(summary.contains("Test Record"));
    }

    @Test
    public void testFetcher() throws Exception {
        DataFetcher fetcher = new DataFetcher();
        String json = "{\"name\":\"Sensor-A\",\"description\":\"Temp\",\"value\":23.5}";
        DataRecord record = fetcher.parseRecord(json);
        assertEquals("Sensor-A", record.getName());
    }
}
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record initial source hashes to detect if user modified code instead of POM
md5sum "$PROJECT_DIR/src/main/java/com/pipeline/DataFetcher.java" > /tmp/initial_source_hashes.txt
md5sum "$PROJECT_DIR/src/main/java/com/pipeline/DataProcessor.java" >> /tmp/initial_source_hashes.txt
chown ga:ga /tmp/initial_source_hashes.txt

# Pre-download dependencies (including the conflicting ones) to speed up init
echo "Pre-warming Maven cache..."
su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn dependency:go-offline -q || true"

# Launch IntelliJ
setup_intellij_project "$PROJECT_DIR" "data-pipeline" 120

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="