#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Generate JavaDoc task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous javadoc output
rm -rf /home/ga/javadoc-output 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# === Create the DevUtils project ===
PROJECT_DIR="/home/ga/eclipse-workspace/DevUtils"
# Clean previous project
rm -rf "$PROJECT_DIR" 2>/dev/null || true

mkdir -p "$PROJECT_DIR/src/com/devutils/text"
mkdir -p "$PROJECT_DIR/src/com/devutils/math"
mkdir -p "$PROJECT_DIR/src/com/devutils/collection"
mkdir -p "$PROJECT_DIR/.settings"

# --- Eclipse project metadata ---
cat > "$PROJECT_DIR/.project" << 'PROJEOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>DevUtils</name>
    <comment>A collection of Java utility classes</comment>
    <projects/>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments/>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
    </natures>
</projectDescription>
PROJEOF

cat > "$PROJECT_DIR/.classpath" << 'CPEOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
CPEOF

cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'PREFS'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
org.eclipse.jdt.core.compiler.release=enabled
PREFS

# --- Source Files (Simplified for brevity, but functional) ---

# 1. StringUtils.java
cat > "$PROJECT_DIR/src/com/devutils/text/StringUtils.java" << 'JAVAEOF'
package com.devutils.text;
/**
 * Utility class providing common string manipulation operations.
 * @author DevUtils Team
 * @since 1.0.0
 */
public final class StringUtils {
    /**
     * Checks if a CharSequence is empty ("") or null.
     * @param cs the CharSequence to check
     * @return true if empty or null
     */
    public static boolean isEmpty(final CharSequence cs) {
        return cs == null || cs.length() == 0;
    }
    /**
     * Reverses a string.
     * @param str the string to reverse
     * @return the reversed string
     */
    public static String reverse(final String str) {
        if (str == null) return null;
        return new StringBuilder(str).reverse().toString();
    }
}
JAVAEOF

# 2. CaseFormat.java
cat > "$PROJECT_DIR/src/com/devutils/text/CaseFormat.java" << 'JAVAEOF'
package com.devutils.text;
/**
 * Utility class for converting between different string case formats.
 * @author DevUtils Team
 * @since 1.1.0
 */
public final class CaseFormat {
    /**
     * Converts camelCase to snake_case.
     * @param camelCase the input string
     * @return the converted string
     */
    public static String camelToSnake(final String camelCase) {
        return camelCase == null ? null : camelCase.replaceAll("([a-z])([A-Z]+)", "$1_$2").toLowerCase();
    }
}
JAVAEOF

# 3. MathUtils.java
cat > "$PROJECT_DIR/src/com/devutils/math/MathUtils.java" << 'JAVAEOF'
package com.devutils.math;
/**
 * Utility class providing common mathematical operations.
 * @author DevUtils Team
 * @since 1.0.0
 */
public final class MathUtils {
    /**
     * Computes the greatest common divisor.
     * @param a first number
     * @param b second number
     * @return the GCD
     */
    public static int gcd(int a, int b) {
        while (b != 0) { int t = b; b = a % b; a = t; }
        return a;
    }
}
JAVAEOF

# 4. Statistics.java
cat > "$PROJECT_DIR/src/com/devutils/math/Statistics.java" << 'JAVAEOF'
package com.devutils.math;
/**
 * Provides basic statistical calculations.
 * @author DevUtils Team
 * @since 1.0.0
 */
public class Statistics {
    /**
     * Computes the mean of an array.
     * @param values input values
     * @return the arithmetic mean
     */
    public static double mean(double[] values) {
        if (values == null || values.length == 0) return 0;
        double sum = 0;
        for (double v : values) sum += v;
        return sum / values.length;
    }
}
JAVAEOF

# 5. ListUtils.java
cat > "$PROJECT_DIR/src/com/devutils/collection/ListUtils.java" << 'JAVAEOF'
package com.devutils.collection;
import java.util.List;
/**
 * Utility class providing operations on List instances.
 * @author DevUtils Team
 * @since 1.0.0
 */
public class ListUtils {
    /**
     * Returns the first element or null.
     * @param list the list
     * @param <T> type of elements
     * @return first element
     */
    public static <T> T first(List<T> list) {
        return (list == null || list.isEmpty()) ? null : list.get(0);
    }
}
JAVAEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Focus and maximize
focus_eclipse_window
sleep 2
dismiss_dialogs 3

# Attempt to Import the project via UI automation
# This is "best effort" - if it fails, the user instructions cover manual import
echo "Attempting to import project..."
DISPLAY=:1 xdotool key alt+f i 2>/dev/null || true # File > Import
sleep 2
DISPLAY=:1 xdotool type "Existing Projects" 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 2
# Select root directory
DISPLAY=:1 xdotool key alt+r 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool type "$PROJECT_DIR" 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true # Validate path
sleep 2
DISPLAY=:1 xdotool key alt+f 2>/dev/null || true # Finish
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true # Just in case

# Final stabilization
sleep 5
dismiss_dialogs 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="