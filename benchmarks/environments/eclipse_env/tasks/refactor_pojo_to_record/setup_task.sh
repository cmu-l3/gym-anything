#!/bin/bash
set -e
echo "=== Setting up refactor_pojo_to_record task ==="

source /workspace/scripts/task_utils.sh

PROJECT_ROOT="/home/ga/eclipse-workspace/RadiationTherapy"

# 1. Clean workspace
rm -rf "$PROJECT_ROOT"
mkdir -p "$PROJECT_ROOT/src/main/java/com/medsys/rt/model"
mkdir -p "$PROJECT_ROOT/src/main/java/com/medsys/rt/service"
mkdir -p "$PROJECT_ROOT/src/test/java/com/medsys/rt/model"

# 2. Create Maven POM
cat > "$PROJECT_ROOT/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.medsys.rt</groupId>
  <artifactId>radiation-therapy-planner</artifactId>
  <version>1.0.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
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
EOF

# 3. Create Legacy POJO (BeamSetup.java)
cat > "$PROJECT_ROOT/src/main/java/com/medsys/rt/model/BeamSetup.java" << 'EOF'
package com.medsys.rt.model;

import java.util.Objects;

/**
 * Represents the geometric setup for a radiation beam.
 * TODO: Refactor to Java Record
 */
public final class BeamSetup {
    private final String beamId;
    private final double gantryAngle;     // IEC 61217 scale: 0-360
    private final double collimatorAngle; // IEC 61217 scale: 0-360

    public BeamSetup(String beamId, double gantryAngle, double collimatorAngle) {
        if (gantryAngle < 0 || gantryAngle > 360) {
            throw new IllegalArgumentException("Gantry angle must be between 0 and 360 degrees");
        }
        this.beamId = beamId;
        this.gantryAngle = gantryAngle;
        this.collimatorAngle = collimatorAngle;
    }

    public String getBeamId() {
        return beamId;
    }

    public double getGantryAngle() {
        return gantryAngle;
    }

    public double getCollimatorAngle() {
        return collimatorAngle;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        BeamSetup that = (BeamSetup) o;
        return Double.compare(that.gantryAngle, gantryAngle) == 0 &&
               Double.compare(that.collimatorAngle, collimatorAngle) == 0 &&
               Objects.equals(beamId, that.beamId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(beamId, gantryAngle, collimatorAngle);
    }

    @Override
    public String toString() {
        return "BeamSetup{" +
                "beamId='" + beamId + '\'' +
                ", gantryAngle=" + gantryAngle +
                ", collimatorAngle=" + collimatorAngle +
                '}';
    }
}
EOF

# 4. Create Dependent Service (TreatmentPlan.java)
cat > "$PROJECT_ROOT/src/main/java/com/medsys/rt/service/TreatmentPlan.java" << 'EOF'
package com.medsys.rt.service;

import com.medsys.rt.model.BeamSetup;
import java.util.ArrayList;
import java.util.List;

public class TreatmentPlan {
    private final List<BeamSetup> beams = new ArrayList<>();

    public void addBeam(BeamSetup beam) {
        System.out.println("Adding beam: " + beam.getBeamId());
        if (beam.getGantryAngle() == 0.0) {
            System.out.println("Warning: Anterior-Posterior beam detected");
        }
        beams.add(beam);
    }

    public void printSummary() {
        for (BeamSetup beam : beams) {
            System.out.printf("Beam %s: Gantry=%.1f, Collimator=%.1f%n",
                beam.getBeamId(), beam.getGantryAngle(), beam.getCollimatorAngle());
        }
    }
}
EOF

# 5. Create Tests (BeamSetupTest.java)
cat > "$PROJECT_ROOT/src/test/java/com/medsys/rt/model/BeamSetupTest.java" << 'EOF'
package com.medsys.rt.model;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class BeamSetupTest {

    @Test
    void testValidBeamSetup() {
        BeamSetup beam = new BeamSetup("B1", 90.0, 0.0);
        // Note: When converting to record, accessors will change from getX() to x()
        // But for the initial state, we test the POJO behavior.
        // The AGENT must update these tests or the record conversion will inherently satisfy equality
        // if they use the standard record features.
        // Actually, let's test behavior that relies on the structure.
        
        assertNotNull(beam);
    }

    @Test
    void testEquality() {
        BeamSetup b1 = new BeamSetup("B1", 90.0, 0.0);
        BeamSetup b2 = new BeamSetup("B1", 90.0, 0.0);
        assertEquals(b1, b2, "Equal objects should match");
        assertEquals(b1.hashCode(), b2.hashCode(), "Hash codes should match");
    }

    @Test
    void testInvalidGantryAngle() {
        Exception exception = assertThrows(IllegalArgumentException.class, () -> {
            new BeamSetup("B_BAD", 400.0, 0.0);
        });
        assertTrue(exception.getMessage().contains("between 0 and 360"));
    }
}
EOF

# 6. Create Eclipse Project Metadata
cat > "$PROJECT_ROOT/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>RadiationTherapy</name>
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

cat > "$PROJECT_ROOT/.classpath" << 'EOF'
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
EOF

# Fix permissions
chown -R ga:ga "$PROJECT_ROOT"

# 7. Start Eclipse
echo "Starting Eclipse..."
wait_for_eclipse 60 || echo "Eclipse did not start automatically, proceeding anyway"

# Focus window
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="