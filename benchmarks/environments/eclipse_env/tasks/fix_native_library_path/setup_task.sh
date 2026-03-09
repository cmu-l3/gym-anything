#!/bin/bash
set -e
echo "=== Setting up fix_native_library_path task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Install build essentials and compile the native library
# We need gcc to compile the stub library. 
# In case it's not installed in the env, we try to install it.
if ! command -v gcc &> /dev/null; then
    echo "Installing gcc..."
    # We are usually ga, so we need sudo. The env config says sudo_nopasswd is true.
    sudo apt-get update -qq && sudo apt-get install -y -qq build-essential
fi

# Create the library directory
sudo mkdir -p /opt/medphys/lib
sudo chmod 755 /opt/medphys/lib

# Find JNI include paths
JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
JAVA_INC="$JAVA_HOME/include"
JAVA_PLATFORM_INC="$JAVA_HOME/include/linux"

# Create C source for the native library
cat > /tmp/dosecalc.c << 'EOF'
#include <jni.h>
#include <stdio.h>

/*
 * Method:    calculateNative
 * Signature: ()D
 */
JNIEXPORT jdouble JNICALL Java_com_hospital_dose_DoseEngine_calculateNative(JNIEnv *env, jobject obj) {
    // Return a specific value to verify the native method was actually called
    return 45.5;
}
EOF

echo "Compiling native library..."
sudo gcc -shared -fPIC \
    -I"$JAVA_INC" \
    -I"$JAVA_PLATFORM_INC" \
    -o /opt/medphys/lib/libdosecalc.so \
    /tmp/dosecalc.c

sudo chmod 644 /opt/medphys/lib/libdosecalc.so
rm /tmp/dosecalc.c

# 2. Create the Eclipse Project
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/DoseCalculator"
SRC_PKG_DIR="$PROJECT_DIR/src/com/hospital/dose"

mkdir -p "$SRC_PKG_DIR"

# .project file
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>DoseCalculator</name>
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
EOF

# .classpath file (Initialized WITHOUT the native library attribute)
cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

# DoseEngine.java (The wrapper class)
cat > "$SRC_PKG_DIR/DoseEngine.java" << 'EOF'
package com.hospital.dose;

public class DoseEngine {
    
    // Load the native library "dosecalc" -> libdosecalc.so
    static {
        try {
            System.loadLibrary("dosecalc");
        } catch (UnsatisfiedLinkError e) {
            System.err.println("CRITICAL ERROR: Failed to load native library 'dosecalc'.");
            System.err.println("Current java.library.path: " + System.getProperty("java.library.path"));
            throw e;
        }
    }
    
    // Native method declaration
    public native double calculateNative();
    
    public double performCalculation() {
        System.out.println("Invoking native dose calculation engine...");
        return calculateNative();
    }
}
EOF

# Main.java (The entry point)
cat > "$SRC_PKG_DIR/Main.java" << 'EOF'
package com.hospital.dose;

import java.io.FileWriter;
import java.io.IOException;

public class Main {
    public static void main(String[] args) {
        System.out.println("=== Starting Dose Verification ===");
        
        try {
            DoseEngine engine = new DoseEngine();
            double result = engine.performCalculation();
            
            System.out.println("Dose calculation successful: " + result + " Gy");
            
            // Write success report
            try (FileWriter writer = new FileWriter("dose_report.txt")) {
                writer.write("Dose Verification Report\n");
                writer.write("------------------------\n");
                writer.write("Status: SUCCESS\n");
                writer.write("Calculation Result: " + result + "\n");
                writer.write("Timestamp: " + System.currentTimeMillis() + "\n");
            } catch (IOException io) {
                io.printStackTrace();
            }
            System.out.println("Report saved to dose_report.txt");
            
        } catch (UnsatisfiedLinkError e) {
            System.err.println("ERROR: Native library not found!");
            System.err.println("Hint: You need to configure the Native Library Location in the Java Build Path.");
            // e.printStackTrace();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
EOF

chown -R ga:ga "$PROJECT_DIR"

# 3. Setup Eclipse
# Wait for Eclipse if it's not running, or ensure it's ready
if ! pgrep -f "eclipse" > /dev/null; then
    echo "Starting Eclipse..."
    # We rely on hooks/post_start to start Eclipse, but if it crashed or isn't there:
    su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data $WORKSPACE_DIR > /dev/null 2>&1 &"
fi

wait_for_eclipse 60

# Focus and maximize
focus_eclipse_window

# Dismiss dialogs
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="