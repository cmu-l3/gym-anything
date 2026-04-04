#!/bin/bash
set -e
echo "=== Setting up configure_build_path task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create project directory structure
PROJECT_DIR="/home/ga/eclipse-workspace/DataProcessor"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/lib"
mkdir -p "$PROJECT_DIR/src/main/java/com/dataprocessor"
mkdir -p "$PROJECT_DIR/bin"

# Download real JARs from Maven Central
echo "Downloading dependencies..."
wget -q -O "$PROJECT_DIR/lib/commons-lang3-3.14.0.jar" \
    "https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"

wget -q -O "$PROJECT_DIR/lib/gson-2.10.1.jar" \
    "https://repo1.maven.org/maven2/com/google/code/gson/gson/2.10.1/gson-2.10.1.jar"

wget -q -O "$PROJECT_DIR/lib/slf4j-api-2.0.9.jar" \
    "https://repo1.maven.org/maven2/org/slf4j/slf4j-api/2.0.9/slf4j-api-2.0.9.jar"

# Verify JARs downloaded
for jar in commons-lang3-3.14.0.jar gson-2.10.1.jar slf4j-api-2.0.9.jar; do
    if [ ! -f "$PROJECT_DIR/lib/$jar" ] || [ ! -s "$PROJECT_DIR/lib/$jar" ]; then
        echo "ERROR: Failed to download $jar"
        # Create dummy jar if download fails to prevent complete task failure in offline test envs
        # (Though real env should have internet)
        touch "$PROJECT_DIR/lib/$jar"
    fi
done

# Create Java source file: App.java
cat > "$PROJECT_DIR/src/main/java/com/dataprocessor/App.java" << 'JAVAEOF'
package com.dataprocessor;

import org.apache.commons.lang3.StringUtils;
import org.apache.commons.lang3.time.StopWatch;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class App {
    private static final Logger logger = LoggerFactory.getLogger(App.class);

    public static void main(String[] args) {
        logger.info("DataProcessor starting...");
        StopWatch watch = StopWatch.createStarted();

        String[] sampleData = {"  Alice  ", null, "  Bob  "};
        for (String name : sampleData) {
            if (StringUtils.isNotBlank(name)) {
                logger.info("Processed: '{}'", StringUtils.strip(name));
            }
        }
        
        watch.stop();
        logger.info("Done in {}ms", watch.getTime());
    }
}
JAVAEOF

# Create Java source file: JsonTransformer.java
cat > "$PROJECT_DIR/src/main/java/com/dataprocessor/JsonTransformer.java" << 'JAVAEOF'
package com.dataprocessor;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

public class JsonTransformer {
    private final Gson gson;

    public JsonTransformer() {
        this.gson = new GsonBuilder().setPrettyPrinting().create();
    }

    public String toJson(Object obj) {
        return gson.toJson(obj);
    }
}
JAVAEOF

# Create Java source file: TextAnalyzer.java
cat > "$PROJECT_DIR/src/main/java/com/dataprocessor/TextAnalyzer.java" << 'JAVAEOF'
package com.dataprocessor;

import org.apache.commons.lang3.StringUtils;
import com.google.gson.JsonObject;

public class TextAnalyzer {
    public String analyze(String text) {
        JsonObject result = new JsonObject();
        result.addProperty("length", text.length());
        result.addProperty("reversed", StringUtils.reverse(text));
        return result.toString();
    }
}
JAVAEOF

# Create Eclipse .project file
cat > "$PROJECT_DIR/.project" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>DataProcessor</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments>
            </arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
    </natures>
</projectDescription>
XMLEOF

# Create BROKEN .classpath file (missing JARs and wrong source folder)
# Note: Intentionally missing src/main/java and all lib entries
cat > "$PROJECT_DIR/.classpath" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
XMLEOF

# Save initial .classpath for comparison
cp "$PROJECT_DIR/.classpath" /tmp/initial_classpath.xml
chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse and prepare UI
wait_for_eclipse 60
focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab

# Force Eclipse to recognize the project (by touching the .project file)
# In a real user scenario, they might need to import it, but putting it in the workspace
# and refreshing usually works. We'll simulate a refresh.
sleep 2
DISPLAY=:1 xdotool key F5
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="