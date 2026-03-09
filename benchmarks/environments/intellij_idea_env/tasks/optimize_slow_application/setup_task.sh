#!/bin/bash
set -e
echo "=== Setting up optimize_slow_application task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/text-analyzer"
PACKAGE_DIR="$PROJECT_DIR/src/main/java/com/textanalyzer"
TEST_DIR="$PROJECT_DIR/src/test/java/com/textanalyzer"
DATA_DIR="$PROJECT_DIR/data"

# Create project structure
mkdir -p "$PACKAGE_DIR"
mkdir -p "$TEST_DIR"
mkdir -p "$DATA_DIR"

echo "Generating project files..."

# 1. pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.textanalyzer</groupId>
  <artifactId>text-analyzer</artifactId>
  <packaging>jar</packaging>
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

# 2. TextFileReader.java (Anti-pattern: String concatenation reading)
cat > "$PACKAGE_DIR/TextFileReader.java" << 'EOF'
package com.textanalyzer;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

public class TextFileReader {
    public List<String> readLines(String filePath) throws IOException {
        File file = new File(filePath);
        FileInputStream fis = new FileInputStream(file);
        String content = "";
        
        // Anti-pattern: Reading byte by byte and concatenating to String
        int data;
        while ((data = fis.read()) != -1) {
            content += (char) data;
        }
        fis.close();
        
        List<String> lines = new ArrayList<>();
        String[] split = content.split("\n");
        for (String line : split) {
            lines.add(line.trim());
        }
        return lines;
    }
}
EOF

# 3. WordCounter.java (Anti-pattern: ArrayList.contains lookup)
cat > "$PACKAGE_DIR/WordCounter.java" << 'EOF'
package com.textanalyzer;

import java.util.ArrayList;
import java.util.List;

public class WordCounter {
    private List<String> words = new ArrayList<>();
    private List<Integer> counts = new ArrayList<>();

    public void countWords(List<String> textLines) {
        for (String line : textLines) {
            String[] tokens = line.split("\\s+");
            for (String token : tokens) {
                if (token.isEmpty()) continue;
                String word = token.toLowerCase().replaceAll("[^a-zA-Z]", "");
                if (word.isEmpty()) continue;
                
                // Anti-pattern: O(n) lookup inside loop
                if (words.contains(word)) {
                    int index = words.indexOf(word);
                    counts.set(index, counts.get(index) + 1);
                } else {
                    words.add(word);
                    counts.add(1);
                }
            }
        }
    }

    public int getCount(String word) {
        if (words.contains(word)) {
            return counts.get(words.indexOf(word));
        }
        return 0;
    }
    
    public int getUniqueWordCount() {
        return words.size();
    }
}
EOF

# 4. DuplicateDetector.java (Anti-pattern: O(n^2) nested loop)
cat > "$PACKAGE_DIR/DuplicateDetector.java" << 'EOF'
package com.textanalyzer;

import java.util.ArrayList;
import java.util.List;

public class DuplicateDetector {
    public int countDuplicateLines(List<String> lines) {
        int duplicates = 0;
        List<String> checked = new ArrayList<>();
        
        // Anti-pattern: Nested loops O(n^2)
        for (int i = 0; i < lines.size(); i++) {
            String current = lines.get(i);
            if (current.isEmpty() || checked.contains(current)) continue;
            
            boolean isDuplicate = false;
            for (int j = i + 1; j < lines.size(); j++) {
                if (lines.get(j).equals(current)) {
                    isDuplicate = true;
                    break;
                }
            }
            
            if (isDuplicate) {
                duplicates++;
            }
            checked.add(current);
        }
        return duplicates;
    }
}
EOF

# 5. ReportGenerator.java (Anti-pattern: String += in loop)
cat > "$PACKAGE_DIR/ReportGenerator.java" << 'EOF'
package com.textanalyzer;

import java.util.List;

public class ReportGenerator {
    public String generateReport(List<String> lines, int totalWords, int uniqueWords) {
        String report = "Analysis Report\n";
        report += "---------------\n";
        report += "Total Lines: " + lines.size() + "\n";
        report += "Total Words: " + totalWords + "\n";
        report += "Unique Words: " + uniqueWords + "\n";
        report += "Sample Content:\n";
        
        // Anti-pattern: String concatenation in loop
        int limit = Math.min(lines.size(), 100);
        for (int i = 0; i < limit; i++) {
            report += "Line " + (i+1) + ": " + lines.get(i) + "\n";
        }
        
        return report;
    }
}
EOF

# 6. TopWordsFinder.java (Anti-pattern: Bubble sort)
cat > "$PACKAGE_DIR/TopWordsFinder.java" << 'EOF'
package com.textanalyzer;

import java.util.ArrayList;
import java.util.List;

public class TopWordsFinder {
    public List<String> findTopNWords(List<String> words, List<Integer> counts, int n) {
        // Create pairs to sort
        List<WordPair> pairs = new ArrayList<>();
        for (int i = 0; i < words.size(); i++) {
            pairs.add(new WordPair(words.get(i), counts.get(i)));
        }
        
        // Anti-pattern: Bubble Sort implementation
        for (int i = 0; i < pairs.size() - 1; i++) {
            for (int j = 0; j < pairs.size() - i - 1; j++) {
                if (pairs.get(j).count < pairs.get(j + 1).count) {
                    // swap
                    WordPair temp = pairs.get(j);
                    pairs.set(j, pairs.get(j + 1));
                    pairs.set(j + 1, temp);
                }
            }
        }
        
        List<String> result = new ArrayList<>();
        for (int i = 0; i < Math.min(n, pairs.size()); i++) {
            result.add(pairs.get(i).word);
        }
        return result;
    }
    
    private static class WordPair {
        String word;
        int count;
        WordPair(String w, int c) { this.word = w; this.count = c; }
    }
}
EOF

# 7. App.java (Main entry)
cat > "$PACKAGE_DIR/App.java" << 'EOF'
package com.textanalyzer;

import java.io.IOException;
import java.util.List;

public class App {
    public static void main(String[] args) {
        System.out.println("Starting Text Analysis...");
        // In a real run, this would be slow with large files
    }
}
EOF

# --- TESTS ---

# 1. TextFileReaderTest.java
cat > "$TEST_DIR/TextFileReaderTest.java" << 'EOF'
package com.textanalyzer;
import org.junit.Test;
import static org.junit.Assert.*;
import java.io.File;
import java.io.FileWriter;
import java.util.List;

public class TextFileReaderTest {
    @Test
    public void testReadLines() throws Exception {
        File temp = File.createTempFile("test", ".txt");
        FileWriter writer = new FileWriter(temp);
        writer.write("Hello\nWorld\nTest");
        writer.close();
        
        TextFileReader reader = new TextFileReader();
        List<String> lines = reader.readLines(temp.getAbsolutePath());
        
        assertEquals(3, lines.size());
        assertEquals("Hello", lines.get(0));
        assertEquals("World", lines.get(1));
        assertEquals("Test", lines.get(2));
    }
}
EOF

# 2. WordCounterTest.java
cat > "$TEST_DIR/WordCounterTest.java" << 'EOF'
package com.textanalyzer;
import org.junit.Test;
import static org.junit.Assert.*;
import java.util.Arrays;

public class WordCounterTest {
    @Test
    public void testCountWords() {
        WordCounter counter = new WordCounter();
        counter.countWords(Arrays.asList("Hello world", "hello Java", "World of Java"));
        
        assertEquals(2, counter.getCount("hello"));
        assertEquals(2, counter.getCount("world"));
        assertEquals(2, counter.getCount("java"));
        assertEquals(1, counter.getCount("of"));
        assertEquals(4, counter.getUniqueWordCount());
    }
}
EOF

# 3. DuplicateDetectorTest.java
cat > "$TEST_DIR/DuplicateDetectorTest.java" << 'EOF'
package com.textanalyzer;
import org.junit.Test;
import static org.junit.Assert.*;
import java.util.Arrays;

public class DuplicateDetectorTest {
    @Test
    public void testCountDuplicateLines() {
        DuplicateDetector detector = new DuplicateDetector();
        int dups = detector.countDuplicateLines(Arrays.asList(
            "Line 1", "Line 2", "Line 1", "Line 3", "Line 2", "Line 2"
        ));
        // "Line 1" is duped once (appears 2x)
        // "Line 2" is duped once (appears 3x) -> logic counts duplicate types or occurrences? 
        // The implemented logic counts how many *unique strings* have duplicates.
        // "Line 1" has dup, "Line 2" has dup. Total 2.
        assertEquals(2, dups);
    }
}
EOF

# 4. ReportGeneratorTest.java
cat > "$TEST_DIR/ReportGeneratorTest.java" << 'EOF'
package com.textanalyzer;
import org.junit.Test;
import static org.junit.Assert.*;
import java.util.Arrays;
import java.util.Collections;

public class ReportGeneratorTest {
    @Test
    public void testGenerateReport() {
        ReportGenerator generator = new ReportGenerator();
        String report = generator.generateReport(Arrays.asList("Line A", "Line B"), 100, 50);
        
        assertTrue(report.contains("Total Lines: 2"));
        assertTrue(report.contains("Total Words: 100"));
        assertTrue(report.contains("Unique Words: 50"));
        assertTrue(report.contains("Line 1: Line A"));
    }
}
EOF

# 5. TopWordsFinderTest.java
cat > "$TEST_DIR/TopWordsFinderTest.java" << 'EOF'
package com.textanalyzer;
import org.junit.Test;
import static org.junit.Assert.*;
import java.util.Arrays;
import java.util.List;

public class TopWordsFinderTest {
    @Test
    public void testFindTopNWords() {
        TopWordsFinder finder = new TopWordsFinder();
        List<String> words = Arrays.asList("a", "b", "c", "d");
        List<Integer> counts = Arrays.asList(10, 50, 20, 5);
        
        List<String> top2 = finder.findTopNWords(words, counts, 2);
        
        assertEquals(2, top2.size());
        assertEquals("b", top2.get(0)); // 50
        assertEquals("c", top2.get(1)); // 20
    }
}
EOF

# Download Real Data
echo "Downloading War and Peace from Gutenberg..."
wget -q -O "$DATA_DIR/war_and_peace.txt" "https://www.gutenberg.org/files/2600/2600-0.txt" || {
    echo "Using fallback data..."
    # Create a 2MB dummy file if download fails
    for i in {1..10000}; do echo "This is a fallback line with some random words repeated." >> "$DATA_DIR/war_and_peace.txt"; done
}

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time.txt

# Open IntelliJ Project
setup_intellij_project "$PROJECT_DIR" "text-analyzer" 180

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="