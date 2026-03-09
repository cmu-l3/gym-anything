#!/bin/bash
set -e
echo "=== Setting up inline_refactoring task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/DataProcessor"
mkdir -p "$PROJECT_DIR/src/main/java/com/dataproc/core"
mkdir -p "$PROJECT_DIR/src/main/java/com/dataproc/app"
mkdir -p "$PROJECT_DIR/src/test/java/com/dataproc/core"
mkdir -p "$PROJECT_DIR/target"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.dataproc</groupId>
  <artifactId>DataProcessor</artifactId>
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
EOF

# 2. Create Validator.java
cat > "$PROJECT_DIR/src/main/java/com/dataproc/core/Validator.java" << 'EOF'
package com.dataproc.core;

public class Validator {
    public static boolean isValid(String input) {
        return input != null && input.length() > 2;
    }
}
EOF

# 3. Create StringProcessor.java (Target for Inlining)
cat > "$PROJECT_DIR/src/main/java/com/dataproc/core/StringProcessor.java" << 'EOF'
package com.dataproc.core;

public class StringProcessor {
    // TARGET 1: Inline this
    public static String trimInput(String s) {
        return s.strip();
    }

    // TARGET 2: Inline this
    public static boolean checkEmpty(String s) {
        return s.isEmpty();
    }

    // Do NOT inline
    public static String normalize(String s) {
        return s.toLowerCase();
    }
}
EOF

# 4. Create MathHelper.java (Target for Inlining)
cat > "$PROJECT_DIR/src/main/java/com/dataproc/core/MathHelper.java" << 'EOF'
package com.dataproc.core;

public class MathHelper {
    // TARGET 3: Inline this
    public static int addValues(int a, int b) {
        return a + b;
    }

    // TARGET 4: Inline this
    public static int computeAbsolute(int x) {
        return Math.abs(x);
    }
}
EOF

# 5. Create DataPipeline.java (The Caller Class)
cat > "$PROJECT_DIR/src/main/java/com/dataproc/core/DataPipeline.java" << 'EOF'
package com.dataproc.core;

public class DataPipeline {
    
    public String process(String rawInput, int base, int bonus) {
        if (rawInput == null) return "Error";
        
        // Call site 1
        String cleaned = StringProcessor.trimInput(rawInput);
        
        // Call site 2
        if (StringProcessor.checkEmpty(cleaned)) {
            return "Empty";
        }
        
        // Call site 3
        if (!invokeValidation(cleaned)) {
            return "Invalid";
        }
        
        // Call site 4
        int score = MathHelper.addValues(base, bonus);
        
        // Call site 5
        int absScore = MathHelper.computeAbsolute(score - 100);
        
        // Call site 6
        return wrapResult(cleaned + ":" + absScore);
    }
    
    // TARGET 5: Inline this
    private boolean invokeValidation(String data) {
        return Validator.isValid(data);
    }
    
    // TARGET 6: Inline this
    private String wrapResult(String result) {
        return "[" + result + "]";
    }
}
EOF

# 6. Create DataPipelineTest.java
cat > "$PROJECT_DIR/src/test/java/com/dataproc/core/DataPipelineTest.java" << 'EOF'
package com.dataproc.core;

import org.junit.Test;
import static org.junit.Assert.*;

public class DataPipelineTest {
    @Test
    public void testProcessHappyPath() {
        DataPipeline pipe = new DataPipeline();
        // Input " hello ", base 50, bonus 60
        // trimmed: "hello"
        // validation: valid
        // score: 50+60 = 110
        // absScore: abs(110-100) = 10
        // result: "[hello:10]"
        String result = pipe.process(" hello ", 50, 60);
        assertEquals("[hello:10]", result);
    }
    
    @Test
    public void testEmpty() {
        DataPipeline pipe = new DataPipeline();
        assertEquals("Empty", pipe.process("   ", 10, 10));
    }
}
EOF

# 7. Create Eclipse .project and .classpath
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>DataProcessor</name>
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
EOF

cat > "$PROJECT_DIR/.classpath" << 'EOF'
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

# Ensure permissions
chown -R ga:ga "$PROJECT_DIR"

# Pre-compile to ensure valid starting state
echo "Verifying initial build..."
su - ga -c "cd $PROJECT_DIR && mvn clean compile test -q"

# Launch/Focus Eclipse
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
dismiss_dialogs 3

# Timestamp
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="