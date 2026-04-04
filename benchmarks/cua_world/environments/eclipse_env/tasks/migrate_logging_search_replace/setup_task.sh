#!/bin/bash
set -e
echo "=== Setting up migrate_logging_search_replace task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Define Project Paths
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_NAME="DataPipeline"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# 3. Clean up previous runs
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/datapipeline/core"
mkdir -p "$PROJECT_DIR/src/main/java/com/datapipeline/io"
mkdir -p "$PROJECT_DIR/src/main/java/com/datapipeline/transform"
mkdir -p "$PROJECT_DIR/src/main/java/com/datapipeline/main"

# 4. Generate Maven Project Files

# pom.xml
cat > "$PROJECT_DIR/pom.xml" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.datapipeline</groupId>
  <artifactId>DataPipeline</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <build>
    <plugins>
      <plugin>
        <groupId>org.codehaus.mojo</groupId>
        <artifactId>exec-maven-plugin</artifactId>
        <version>3.1.0</version>
        <configuration>
          <mainClass>com.datapipeline.main.Main</mainClass>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOF

# Core Classes (with System.out.println)
cat > "$PROJECT_DIR/src/main/java/com/datapipeline/core/Pipeline.java" <<EOF
package com.datapipeline.core;

import java.util.ArrayList;
import java.util.List;

public class Pipeline {
    private List<String> stages = new ArrayList<>();

    public void addStage(String stage) {
        System.out.println("Adding stage: " + stage);
        stages.add(stage);
    }

    public void execute() {
        System.out.println("Starting pipeline execution...");
        for (String stage : stages) {
            System.out.println("Executing stage: " + stage);
            try {
                Thread.sleep(100);
            } catch (InterruptedException e) {
                System.err.println("Pipeline interrupted: " + e.getMessage());
            }
        }
        System.out.println("Pipeline execution finished.");
    }
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/datapipeline/core/DataRecord.java" <<EOF
package com.datapipeline.core;

public class DataRecord {
    private String id;
    private String data;

    public DataRecord(String id, String data) {
        this.id = id;
        this.data = data;
        System.out.println("Created new DataRecord: " + id);
    }

    public void validate() {
        if (data == null || data.isEmpty()) {
            System.err.println("Validation failed for record " + id + ": Data is empty");
        } else {
            System.out.println("Record " + id + " is valid.");
        }
    }
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/datapipeline/core/PipelineConfig.java" <<EOF
package com.datapipeline.core;

public class PipelineConfig {
    public void load() {
        System.out.println("Loading configuration from default path...");
        // Simulation of loading config
        System.out.println("Configuration loaded successfully.");
    }
}
EOF

# IO Classes
cat > "$PROJECT_DIR/src/main/java/com/datapipeline/io/CsvDataReader.java" <<EOF
package com.datapipeline.io;

public class CsvDataReader {
    public void read(String path) {
        System.out.println("Opening CSV file: " + path);
        if (!path.endsWith(".csv")) {
            System.err.println("Error: File is not a CSV: " + path);
            return;
        }
        System.out.println("Reading headers...");
        System.out.println("Reading rows...");
        System.out.println("Finished reading CSV.");
    }
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/datapipeline/io/JsonDataWriter.java" <<EOF
package com.datapipeline.io;

public class JsonDataWriter {
    public void write(String path) {
        System.out.println("Initializing JSON writer...");
        System.out.println("Writing data to " + path);
        System.out.println("Closing file stream.");
    }
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/datapipeline/io/FileManager.java" <<EOF
package com.datapipeline.io;

public class FileManager {
    public void checkDiskSpace() {
        System.out.println("Checking available disk space...");
        System.out.println("Disk space OK.");
    }
    
    public void backup() {
        System.out.println("Starting backup process...");
    }
}
EOF

# Transform Classes
cat > "$PROJECT_DIR/src/main/java/com/datapipeline/transform/FilterStage.java" <<EOF
package com.datapipeline.transform;

public class FilterStage {
    public void filter(String criteria) {
        System.out.println("Initializing filter with criteria: " + criteria);
        System.out.println("Filtering data...");
        System.out.println("Filter complete. Removed 0 records.");
    }
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/datapipeline/transform/MapStage.java" <<EOF
package com.datapipeline.transform;

public class MapStage {
    public void mapFields() {
        System.out.println("Mapping input fields to output schema...");
        System.out.println("Mapping complete.");
    }
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/datapipeline/transform/AggregateStage.java" <<EOF
package com.datapipeline.transform;

public class AggregateStage {
    public void aggregate() {
        System.out.println("Grouping data by key...");
        System.out.println("Calculating averages...");
        System.out.println("Aggregation finished.");
    }
}
EOF

# Main Class (Contains the ONE whitelisted System.out.println)
cat > "$PROJECT_DIR/src/main/java/com/datapipeline/main/Main.java" <<EOF
package com.datapipeline.main;

import com.datapipeline.core.*;
import com.datapipeline.io.*;
import com.datapipeline.transform.*;

public class Main {
    public static void main(String[] args) {
        System.out.println("--- Data Pipeline Application Starting ---"); // Should be logged
        
        PipelineConfig config = new PipelineConfig();
        config.load();
        
        CsvDataReader reader = new CsvDataReader();
        reader.read("data.csv");
        
        DataRecord record = new DataRecord("REC-001", "Sample Data");
        record.validate();
        
        FilterStage filter = new FilterStage();
        filter.filter("active=true");
        
        Pipeline pipeline = new Pipeline();
        pipeline.addStage("Ingest");
        pipeline.addStage("Process");
        pipeline.execute();
        
        // THIS IS THE ONLY LINE THAT SHOULD REMAIN AS SYSTEM.OUT.PRINTLN
        System.out.println("PIPELINE_RESULT=SUCCESS: Processed 100 records in 250ms");
    }
}
EOF

# 5. Generate Eclipse Metadata (.project and .classpath)
# This makes it appear as an imported project without needing manual import steps

cat > "$PROJECT_DIR/.project" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>DataPipeline</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments>
            </arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
            <arguments>
            </arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOF

cat > "$PROJECT_DIR/.classpath" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# 6. Count initial print statements for verification
grep -r "System.out.println" "$PROJECT_DIR/src" | wc -l > /tmp/initial_println_count.txt
grep -r "System.err.println" "$PROJECT_DIR/src" | wc -l > /tmp/initial_err_count.txt

# 7. Start Eclipse
# Ensure Eclipse is running and sees the project
if ! pgrep -f "eclipse" > /dev/null; then
    su - ga -c "nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace > /tmp/eclipse.log 2>&1 &"
    sleep 15
fi

# Wait for Eclipse window
wait_for_eclipse 60

# Maximize window
focus_eclipse_window
sleep 2

# Dismiss any dialogs
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="