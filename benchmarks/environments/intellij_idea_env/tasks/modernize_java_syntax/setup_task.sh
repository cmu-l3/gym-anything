#!/bin/bash
set -e
echo "=== Setting up modernize_java_syntax task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/legacy-modernize"
mkdir -p "$PROJECT_DIR/src/main/java/com/legacy"
mkdir -p "$PROJECT_DIR/src/test/java/com/legacy"

# 1. Create POM
cat > "$PROJECT_DIR/pom.xml" << 'pomEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.legacy</groupId>
  <artifactId>legacy-modernize</artifactId>
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
pomEOF

# 2. Create Legacy Source Files

# DataProcessor.java (Anonymous Comparator, Explicit Generics, Iterator loop)
cat > "$PROJECT_DIR/src/main/java/com/legacy/DataProcessor.java" << 'javaEOF'
package com.legacy;

import java.util.*;

public class DataProcessor {
    public List<String> sortData(List<String> input) {
        // Legacy: Explicit types in constructor
        List<String> copy = new ArrayList<String>(input);
        
        // Legacy: Anonymous Comparator
        Collections.sort(copy, new Comparator<String>() {
            @Override
            public int compare(String s1, String s2) {
                return s1.length() - s2.length();
            }
        });
        return copy;
    }

    public int countLongWords(List<String> input) {
        int count = 0;
        // Legacy: Iterator loop
        Iterator<String> it = input.iterator();
        while (it.hasNext()) {
            String s = it.next();
            if (s.length() > 5) {
                count++;
            }
        }
        return count;
    }
}
javaEOF

# FileHandler.java (Try-finally manual close)
cat > "$PROJECT_DIR/src/main/java/com/legacy/FileHandler.java" << 'javaEOF'
package com.legacy;

import java.io.*;

public class FileHandler {
    public String readHeader(File file) throws IOException {
        FileInputStream fis = null;
        try {
            fis = new FileInputStream(file);
            BufferedReader reader = null;
            try {
                reader = new BufferedReader(new InputStreamReader(fis));
                return reader.readLine();
            } finally {
                if (reader != null) {
                    reader.close();
                }
            }
        } finally {
            if (fis != null) {
                fis.close();
            }
        }
    }
}
javaEOF

# EventSystem.java (Anonymous Runnable, Consumer)
cat > "$PROJECT_DIR/src/main/java/com/legacy/EventSystem.java" << 'javaEOF'
package com.legacy;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

public class EventSystem {
    public void processEvents(ExecutorService executor) {
        // Legacy: Anonymous Runnable
        executor.submit(new Runnable() {
            @Override
            public void run() {
                System.out.println("Processing started");
            }
        });
    }

    public void handleString(String s, Consumer<String> handler) {
        handler.accept(s);
    }

    public void trigger() {
        // Legacy: Anonymous Consumer
        handleString("Event", new Consumer<String>() {
            @Override
            public void accept(String s) {
                System.out.println("Handled: " + s);
            }
        });
    }
}
javaEOF

# ConfigParser.java (Old Switch)
cat > "$PROJECT_DIR/src/main/java/com/legacy/ConfigParser.java" << 'javaEOF'
package com.legacy;

public class ConfigParser {
    public int getTimeout(String profile) {
        int timeout;
        // Legacy: Old switch statement
        switch (profile) {
            case "dev":
                timeout = 1000;
                break;
            case "prod":
            case "production":
                timeout = 5000;
                break;
            case "test":
                timeout = 200;
                break;
            default:
                timeout = 1000;
        }
        return timeout;
    }
}
javaEOF

# ReportGenerator.java (String concatenation)
cat > "$PROJECT_DIR/src/main/java/com/legacy/ReportGenerator.java" << 'javaEOF'
package com.legacy;

public class ReportGenerator {
    public String generateHtmlReport(String title, String content) {
        // Legacy: String concatenation for multi-line
        String html = "<html>\n" +
                      "  <body>\n" +
                      "    <h1>" + title + "</h1>\n" +
                      "    <p>" + content + "</p>\n" +
                      "  </body>\n" +
                      "</html>";
        return html;
    }
}
javaEOF

# 3. Create Tests
cat > "$PROJECT_DIR/src/test/java/com/legacy/ModernizationTest.java" << 'javaEOF'
package com.legacy;

import org.junit.Test;
import java.io.*;
import java.util.*;
import static org.junit.Assert.*;

public class ModernizationTest {
    @Test
    public void testDataProcessor() {
        DataProcessor dp = new DataProcessor();
        List<String> input = Arrays.asList("apple", "banana", "kiwi", "pineapple");
        List<String> sorted = dp.sortData(input);
        assertEquals("kiwi", sorted.get(0));
        assertEquals("pineapple", sorted.get(3));
        assertEquals(2, dp.countLongWords(input));
    }

    @Test
    public void testConfigParser() {
        ConfigParser cp = new ConfigParser();
        assertEquals(1000, cp.getTimeout("dev"));
        assertEquals(5000, cp.getTimeout("prod"));
        assertEquals(200, cp.getTimeout("test"));
        assertEquals(1000, cp.getTimeout("unknown"));
    }

    @Test
    public void testReportGenerator() {
        ReportGenerator rg = new ReportGenerator();
        String report = rg.generateHtmlReport("Title", "Content");
        assertTrue(report.contains("<h1>Title</h1>"));
        assertTrue(report.contains("<html>"));
    }

    @Test
    public void testFileHandler() throws IOException {
        FileHandler fh = new FileHandler();
        File tmp = File.createTempFile("test", ".txt");
        FileWriter fw = new FileWriter(tmp);
        fw.write("HeaderLine\nBody");
        fw.close();
        assertEquals("HeaderLine", fh.readHeader(tmp));
        tmp.delete();
    }
}
javaEOF

# 4. Set ownership and initial check
chown -R ga:ga "$PROJECT_DIR"

# Verify it compiles initially
echo "Verifying initial project state..."
su - ga -c "cd $PROJECT_DIR && mvn compile -q && mvn test -q"

# Record file checksums
find "$PROJECT_DIR/src/main/java" -type f -exec md5sum {} + > /tmp/initial_checksums.txt
date +%s > /tmp/task_start_time.txt

# 5. Open in IntelliJ
setup_intellij_project "$PROJECT_DIR" "legacy-modernize" 120

take_screenshot /tmp/task_start.png
echo "=== Setup complete ==="