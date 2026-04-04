#!/bin/bash
echo "=== Setting up Compare and Merge Task ==="

source /workspace/scripts/task_utils.sh

# Define project paths
PROJECT_ROOT="/home/ga/eclipse-workspace/MergeTask"
PKG_DIR="$PROJECT_ROOT/src/main/java/com/acme/util"
TEST_PKG_DIR="$PROJECT_ROOT/src/test/java/com/acme/util"
LIB_DIR="$PROJECT_ROOT/lib"

# Clean up previous runs
rm -rf "$PROJECT_ROOT" 2>/dev/null || true

# Create directory structure
mkdir -p "$PKG_DIR"
mkdir -p "$TEST_PKG_DIR"
mkdir -p "$LIB_DIR"

# Download JUnit 5 Standalone Console for verification (running tests outside Eclipse)
if [ ! -f "/usr/share/java/junit-platform-console-standalone.jar" ]; then
    echo "Downloading JUnit Platform Console..."
    mkdir -p /usr/share/java
    wget -q -O /usr/share/java/junit-platform-console-standalone.jar https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/1.9.3/junit-platform-console-standalone-1.9.3.jar
fi
# Copy to project lib for agent use (optional, but good practice)
cp /usr/share/java/junit-platform-console-standalone.jar "$LIB_DIR/"

# ==============================================================================
# Generate DataProcessor_v1.java (Robust, good docs, old algorithms)
# ==============================================================================
cat > "$PKG_DIR/DataProcessor_v1.java" << 'EOF'
package com.acme.util;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Utility class for processing data strings.
 * 
 * @author SeniorDev
 * @version 1.0
 * @since 2023-01-15
 */
public class DataProcessor_v1 {

    private static final Pattern HTML_TAGS = Pattern.compile("<[^>]*>");

    /**
     * Parses a CSV line handling quoted fields correctly.
     * 
     * @param line the CSV line to parse
     * @return List of fields
     */
    public List<String> parseCSVLine(String line) {
        if (line == null) {
            return new ArrayList<>();
        }
        
        List<String> result = new ArrayList<>();
        boolean inQuotes = false;
        StringBuilder currentField = new StringBuilder();
        
        for (char c : line.toCharArray()) {
            if (c == '\"') {
                inQuotes = !inQuotes;
            } else if (c == ',' && !inQuotes) {
                result.add(currentField.toString());
                currentField.setLength(0);
            } else {
                currentField.append(c);
            }
        }
        result.add(currentField.toString());
        return result;
    }

    /**
     * Normalizes whitespace in a string, handling Unicode spaces.
     * 
     * @param input the input string
     * @return string with normalized spaces
     */
    public String normalizeWhitespace(String input) {
        if (input == null) return null;
        // v1 uses Unicode property for separators
        return input.replaceAll("\\p{Zs}+", " ").trim();
    }
    
    /**
     * Removes HTML tags from string.
     * 
     * @param input HTML string
     * @return Plain text
     */
    public String sanitizeHTML(String input) {
        if (input == null) return null;
        return HTML_TAGS.matcher(input).replaceAll("");
    }
    
    /**
     * Computes average of a list of numbers.
     * Note: Standard sequential processing.
     */
    public double computeStatistics(List<Double> numbers) {
        if (numbers == null || numbers.isEmpty()) return 0.0;
        double sum = 0;
        for (Double n : numbers) {
            sum += n;
        }
        return sum / numbers.size();
    }
}
EOF

# ==============================================================================
# Generate DataProcessor_v2.java (New features, optimization, poor docs)
# ==============================================================================
cat > "$PKG_DIR/DataProcessor_v2.java" << 'EOF'
package com.acme.util;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

public class DataProcessor_v2 {

    // v2 naive implementation - breaks on commas inside quotes
    public List<String> parseCSVLine(String line) {
        List<String> list = new ArrayList<>();
        String[] tokens = line.split(",");
        for(String t : tokens) list.add(t);
        return list;
    }

    // v2 only handles standard ASCII space
    public String normalizeWhitespace(String input) {
        return input.replaceAll("\\s+", " ").trim();
    }

    // Optimized parallel stream implementation
    public double computeStatistics(List<Double> numbers) {
        if (numbers == null || numbers.isEmpty()) return 0.0;
        return numbers.parallelStream()
                      .mapToDouble(Double::doubleValue)
                      .average()
                      .orElse(0.0);
    }
    
    // NEW FEATURE in v2
    public Map<String, String> transformToMap(List<String> keys, List<String> values) {
        Map<String, String> map = new HashMap<>();
        if (keys == null || values == null) return map;
        int size = Math.min(keys.size(), values.size());
        for (int i = 0; i < size; i++) {
            map.put(keys.get(i), values.get(i));
        }
        return map;
    }
    
    // NEW FEATURE in v2
    public boolean validateEmail(String email) {
        if (email == null) return false;
        return email.matches("^[A-Za-z0-9+_.-]+@(.+)$");
    }
}
EOF

# ==============================================================================
# Create Empty Target File
# ==============================================================================
touch "$PKG_DIR/DataProcessor.java"

# ==============================================================================
# Generate JUnit Test
# ==============================================================================
cat > "$TEST_PKG_DIR/DataProcessorTest.java" << 'EOF'
package com.acme.util;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

public class DataProcessorTest {

    private final DataProcessor processor = new DataProcessor();

    @Test
    void testParseCSVLine_Complex() {
        // v1 handles this correctly, v2 does not
        String line = "John,\"Doe, Jr.\",New York";
        List<String> result = processor.parseCSVLine(line);
        assertEquals(3, result.size(), "Should handle commas inside quotes (Use v1 implementation)");
        assertEquals("Doe, Jr.", result.get(1));
    }

    @Test
    void testNormalizeWhitespace_Unicode() {
        // v1 handles unicode spaces (\u00A0 is non-breaking space)
        String input = "Hello\u00A0World"; 
        String result = processor.normalizeWhitespace(input);
        assertEquals("Hello World", result, "Should normalize unicode spaces (Use v1 implementation)");
    }

    @Test
    void testComputeStatistics_Parallel() {
        List<Double> nums = Arrays.asList(1.0, 2.0, 3.0, 4.0, 5.0);
        assertEquals(3.0, processor.computeStatistics(nums), 0.001);
    }
    
    @Test
    void testSanitizeHTML_Exists() {
        // Only in v1
        String html = "<div>Hello</div>";
        assertEquals("Hello", processor.sanitizeHTML(html), "Method sanitizeHTML should exist (from v1)");
    }

    @Test
    void testValidateEmail_Exists() {
        // Only in v2
        assertTrue(processor.validateEmail("test@example.com"), "Method validateEmail should exist (from v2)");
        assertFalse(processor.validateEmail("invalid-email"), "Email validation should work");
    }

    @Test
    void testTransformToMap_Exists() {
        // Only in v2
        List<String> keys = Arrays.asList("k1", "k2");
        List<String> vals = Arrays.asList("v1", "v2");
        Map<String, String> map = processor.transformToMap(keys, vals);
        assertEquals("v1", map.get("k1"), "Method transformToMap should exist (from v2)");
    }
}
EOF

# ==============================================================================
# Generate Merge Instructions
# ==============================================================================
cat > "$PROJECT_ROOT/MERGE_INSTRUCTIONS.md" << 'EOF'
# Merge Instructions for DataProcessor.java

You need to create a final `DataProcessor.java` by merging `DataProcessor_v1.java` and `DataProcessor_v2.java`.

Follow these specific rules:

1. **Class Javadoc**: Use Version 1's class-level Javadoc (with @author and @since tags).
2. **`parseCSVLine`**: Use Version 1 (it handles quoted fields correctly).
3. **`computeStatistics`**: Use Version 2 (it uses parallel streams for performance).
4. **`normalizeWhitespace`**: Use Version 1 (it handles Unicode characters).
5. **`transformToMap`**: Include this new method from Version 2.
6. **`validateEmail`**: Include this new method from Version 2.
7. **`sanitizeHTML`**: Keep this method from Version 1.

The final class must be named `DataProcessor` and reside in package `com.acme.util`.
Ensure all necessary imports from both files are included.
EOF

# ==============================================================================
# Create Eclipse Project Metadata (.project, .classpath)
# ==============================================================================
cat > "$PROJECT_ROOT/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>MergeTask</name>
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

# Note: We include the junit-platform-console jar in classpath for test running
cat > "$PROJECT_ROOT/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src/main/java"/>
    <classpathentry kind="src" path="src/test/java"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
    <classpathentry kind="lib" path="lib/junit-platform-console-standalone.jar"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
EOF

chown -R ga:ga "$PROJECT_ROOT"

# ==============================================================================
# Initial State Recording
# ==============================================================================
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/compile_success.txt

# Start Eclipse
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
dismiss_dialogs 3
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="