#!/bin/bash
set -e
echo "=== Setting up optimize_string_concatenation task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="MediLogExport"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# 1. Create Project Structure
mkdir -p "$PROJECT_DIR/src/main/java/com/medilog/export"
mkdir -p "$PROJECT_DIR/src/test/java/com/medilog/export"

# 2. Create pom.xml (Maven Project)
cat > "$PROJECT_DIR/pom.xml" << 'EOFPOM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.medilog</groupId>
  <artifactId>MediLogExport</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <name>MediLogExport</name>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter-api</artifactId>
      <version>5.9.2</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter-engine</artifactId>
      <version>5.9.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
EOFPOM

# 3. Create Domain Class (Observation.java)
cat > "$PROJECT_DIR/src/main/java/com/medilog/export/Observation.java" << 'EOFJAVA'
package com.medilog.export;

public class Observation {
    private int id;
    private String type; // e.g., NM (Numeric), ST (String)
    private String identifier; // e.g., 8867-4
    private String value;
    private String units;
    private String status; // F (Final), C (Corrected)

    public Observation(int id, String type, String identifier, String value, String units, String status) {
        this.id = id;
        this.type = type;
        this.identifier = identifier;
        this.value = value;
        this.units = units;
        this.status = status;
    }

    public int getId() { return id; }
    public String getType() { return type; }
    public String getIdentifier() { return identifier; }
    public String getValue() { return value; }
    public String getUnits() { return units; }
    public String getStatus() { return status; }
}
EOFJAVA

# 4. Create Target Class with Inefficient Code (HL7MessageBuilder.java)
cat > "$PROJECT_DIR/src/main/java/com/medilog/export/HL7MessageBuilder.java" << 'EOFJAVA'
package com.medilog.export;

import java.util.List;

public class HL7MessageBuilder {

    /**
     * Generates HL7 OBX segments for a list of observations.
     * WARNING: This method is currently a performance bottleneck.
     */
    public String buildObservationSegment(List<Observation> observations) {
        // TODO: Refactor this to use StringBuilder for better performance
        String result = "";
        
        for (Observation obs : observations) {
            // OBX|SetID|ValueType|ObservationIdentifier||ObservationValue|Units||||ObservationResultStatus
            result += "OBX|" + obs.getId() + "|" + obs.getType() + "|" + obs.getIdentifier() + "||" 
                   + obs.getValue() + "|" + obs.getUnits() + "||||" + obs.getStatus() + "\r";
        }
        
        return result;
    }
}
EOFJAVA

# 5. Create Test Class (HL7MessageBuilderTest.java)
cat > "$PROJECT_DIR/src/main/java/com/medilog/export/Main.java" << 'EOFJAVA'
package com.medilog.export;

public class Main {
    public static void main(String[] args) {
        System.out.println("MediLog Export System v1.0");
    }
}
EOFJAVA

cat > "$PROJECT_DIR/src/test/java/com/medilog/export/HL7MessageBuilderTest.java" << 'EOFJAVA'
package com.medilog.export;

import static org.junit.jupiter.api.Assertions.assertEquals;
import org.junit.jupiter.api.Test;
import java.util.ArrayList;
import java.util.List;

public class HL7MessageBuilderTest {

    @Test
    public void testBuildObservationSegment() {
        List<Observation> obsList = new ArrayList<>();
        obsList.add(new Observation(1, "NM", "8867-4^Heart Rate", "72", "/min", "F"));
        obsList.add(new Observation(2, "NM", "8310-5^Body Temp", "37.2", "Cel", "F"));
        obsList.add(new Observation(3, "ST", "Symptoms", "Cough", "", "F"));

        HL7MessageBuilder builder = new HL7MessageBuilder();
        String result = builder.buildObservationSegment(obsList);

        String expected = "OBX|1|NM|8867-4^Heart Rate||72|/min||||F\r" +
                          "OBX|2|NM|8310-5^Body Temp||37.2|Cel||||F\r" +
                          "OBX|3|ST|Symptoms||Cough|||||F\r";

        assertEquals(expected, result, "The generated HL7 segments do not match the expected format.");
    }
    
    @Test
    public void testEmptyList() {
        HL7MessageBuilder builder = new HL7MessageBuilder();
        String result = builder.buildObservationSegment(new ArrayList<>());
        assertEquals("", result, "Result should be empty for empty list");
    }
}
EOFJAVA

# 6. Generate Eclipse Project Metadata
# .project
cat > "$PROJECT_DIR/.project" << 'EOFPROJECT'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>MediLogExport</name>
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
EOFPROJECT

# .classpath
cat > "$PROJECT_DIR/.classpath" << 'EOFCLASSPATH'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="src" output="target/test-classes" path="src/test/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
            <attribute name="test" value="true"/>
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
EOFCLASSPATH

# 7. Set Permissions
chown -R ga:ga "$PROJECT_DIR"

# 8. Record Start Time and Initial File Hash
date +%s > /tmp/task_start_time.txt
sha256sum "$PROJECT_DIR/src/main/java/com/medilog/export/HL7MessageBuilder.java" > /tmp/initial_file_hash.txt

# 9. Pre-warm Maven (download dependencies) to speed up user experience
echo "Pre-warming Maven dependencies..."
cd "$PROJECT_DIR"
su - ga -c "mvn dependency:resolve -q" || echo "Maven warm-up failed, continuing..."

# 10. Launch Eclipse
echo "Launching Eclipse..."
# Start Eclipse using the helper from task_utils or directly
if ! pgrep -f "eclipse" > /dev/null; then
    su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace -nosplash > /tmp/eclipse.log 2>&1 &"
fi

wait_for_eclipse 120

# Maximize and focus
focus_eclipse_window

# Dismiss welcome
dismiss_dialogs 5
close_welcome_tab

# Wait for workspace to stabilize and project to be scanned
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="