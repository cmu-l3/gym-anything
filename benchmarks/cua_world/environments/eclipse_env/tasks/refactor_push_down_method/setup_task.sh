#!/bin/bash
echo "=== Setting up refactor_push_down_method task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="LogisticsSystem"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# clean up any existing project
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/src/main/java/com/logistics/domain"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOFPOM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.logistics</groupId>
  <artifactId>logistics-system</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
EOFPOM

# 2. Create Transport.java (The Superclass with members to push down)
cat > "$PROJECT_DIR/src/main/java/com/logistics/domain/Transport.java" << 'EOFJAVA'
package com.logistics.domain;

public abstract class Transport {
    
    private String id;
    private double weight;
    
    // THIS SHOULD BE PUSHED DOWN
    private static final int MAX_TIRE_PSI = 110;

    public Transport(String id, double weight) {
        this.id = id;
        this.weight = weight;
    }

    public String getId() {
        return id;
    }

    public double getWeight() {
        return weight;
    }

    // THIS SHOULD BE PUSHED DOWN
    public boolean checkTirePressure() {
        System.out.println("Checking tire pressure against max: " + MAX_TIRE_PSI);
        return true;
    }
    
    public abstract void move();
}
EOFJAVA

# 3. Create Subclasses
cat > "$PROJECT_DIR/src/main/java/com/logistics/domain/Truck.java" << 'EOFJAVA'
package com.logistics.domain;

public class Truck extends Transport {

    public Truck(String id, double weight) {
        super(id, weight);
    }

    @Override
    public void move() {
        System.out.println("Driving on road...");
    }
}
EOFJAVA

cat > "$PROJECT_DIR/src/main/java/com/logistics/domain/Ship.java" << 'EOFJAVA'
package com.logistics.domain;

public class Ship extends Transport {

    public Ship(String id, double weight) {
        super(id, weight);
    }

    @Override
    public void move() {
        System.out.println("Sailing on water...");
    }
}
EOFJAVA

cat > "$PROJECT_DIR/src/main/java/com/logistics/domain/Drone.java" << 'EOFJAVA'
package com.logistics.domain;

public class Drone extends Transport {

    public Drone(String id, double weight) {
        super(id, weight);
    }

    @Override
    public void move() {
        System.out.println("Flying in air...");
    }
}
EOFJAVA

# 4. Create Main.java to test compilation
cat > "$PROJECT_DIR/src/main/java/com/logistics/domain/Main.java" << 'EOFJAVA'
package com.logistics.domain;

public class Main {
    public static void main(String[] args) {
        Truck t = new Truck("T-1", 5000);
        t.move();
        
        // In the initial state, this is valid on Transport (inherited)
        // After refactoring, t.checkTirePressure() should still be valid on Truck
        System.out.println("Tire check: " + t.checkTirePressure());
        
        Ship s = new Ship("S-1", 20000);
        // In initial state, this works (but is logically wrong)
        // After refactoring, s.checkTirePressure() would be a compile error if called here.
        // We comment it out so Main compiles after refactoring IF the user updates references manually,
        // but typically Push Down doesn't update callsites that rely on the supertype unless necessary.
        // For this task, we assume the agent just moves the method definition.
        // We actually want the 'checkTirePressure' call on 't' (Truck) to succeed.
        // We won't include a call on Ship in Main because it would break compilation after refactoring,
        // and we want 'mvn compile' to succeed as a success criterion.
        s.move();
    }
}
EOFJAVA

# 5. Create Eclipse Metadata
cat > "$PROJECT_DIR/.project" << 'EOFPROJECT'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>LogisticsSystem</name>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOFPROJECT

cat > "$PROJECT_DIR/.classpath" << 'EOFCLASSPATH'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java"/>
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

chown -R ga:ga "$PROJECT_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start Eclipse
echo "Starting Eclipse..."
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab

# Allow Eclipse to index
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="