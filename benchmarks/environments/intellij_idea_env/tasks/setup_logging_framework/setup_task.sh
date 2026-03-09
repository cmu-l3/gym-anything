#!/bin/bash
set -e
echo "=== Setting up setup_logging_framework task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/library-app"
mkdir -p "$PROJECT_DIR/src/main/java/com/library/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/library/repository"
mkdir -p "$PROJECT_DIR/src/main/java/com/library/service"
mkdir -p "$PROJECT_DIR/src/main/java/com/library/util"
mkdir -p "$PROJECT_DIR/src/main/resources"

# 1. Create pom.xml (Initial state: no logging deps)
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.library</groupId>
    <artifactId>library-app</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <!-- No logging framework yet -->
    </dependencies>
</project>
POMEOF

# 2. Create Model (No prints here)
cat > "$PROJECT_DIR/src/main/java/com/library/model/Book.java" << 'JAVAEOF'
package com.library.model;

public class Book {
    private String id;
    private String title;
    private String author;

    public Book(String id, String title, String author) {
        this.id = id;
        this.title = title;
        this.author = author;
    }

    public String getTitle() { return title; }
    public String getAuthor() { return author; }
    
    @Override
    public String toString() {
        return "Book{" + "id='" + id + "', title='" + title + "'}";
    }
}
JAVAEOF

# 3. Create Repository (Has prints)
cat > "$PROJECT_DIR/src/main/java/com/library/repository/BookRepository.java" << 'JAVAEOF'
package com.library.repository;

import com.library.model.Book;
import java.util.ArrayList;
import java.util.List;

public class BookRepository {
    public List<Book> findAll() {
        System.out.println("DEBUG: Accessing database to retrieve all books");
        // Simulate DB
        List<Book> books = new ArrayList<>();
        books.add(new Book("1", "The Great Gatsby", "F. Scott Fitzgerald"));
        System.out.println("INFO: Retrieved " + books.size() + " books");
        return books;
    }

    public void save(Book book) {
        try {
            System.out.println("DEBUG: Attempting to save book: " + book);
            if (book.getTitle() == null) {
                throw new IllegalArgumentException("Title cannot be null");
            }
            System.out.println("INFO: Book saved successfully");
        } catch (Exception e) {
            System.err.println("ERROR: Failed to save book: " + e.getMessage());
        }
    }
}
JAVAEOF

# 4. Create Service (Has prints)
cat > "$PROJECT_DIR/src/main/java/com/library/service/BookService.java" << 'JAVAEOF'
package com.library.service;

import com.library.repository.BookRepository;
import com.library.model.Book;
import java.util.List;

public class BookService {
    private final BookRepository repository = new BookRepository();

    public void processBooks() {
        System.out.println("INFO: Starting book processing");
        List<Book> books = repository.findAll();
        
        if (books.isEmpty()) {
            System.out.println("WARN: No books found in repository");
            return;
        }

        for (Book book : books) {
            System.out.println("DEBUG: Processing " + book.getTitle());
        }
        System.out.println("INFO: Processing complete");
    }
}
JAVAEOF

# 5. Create Util (Has prints)
cat > "$PROJECT_DIR/src/main/java/com/library/util/SearchEngine.java" << 'JAVAEOF'
package com.library.util;

public class SearchEngine {
    public void index() {
        long start = System.currentTimeMillis();
        System.out.println("INFO: Starting search index update");
        
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            System.err.println("ERROR: Indexing interrupted");
        }
        
        long end = System.currentTimeMillis();
        System.out.println("DEBUG: Indexing took " + (end - start) + "ms");
    }
}
JAVAEOF

# 6. Create Main App (Has prints)
cat > "$PROJECT_DIR/src/main/java/com/library/LibraryApp.java" << 'JAVAEOF'
package com.library;

import com.library.service.BookService;
import com.library.util.SearchEngine;

public class LibraryApp {
    public static void main(String[] args) {
        System.out.println("INFO: Application starting up...");
        
        SearchEngine engine = new SearchEngine();
        engine.index();
        
        BookService service = new BookService();
        service.processBooks();
        
        System.out.println("INFO: Application shutting down");
    }
}
JAVAEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Verify initial compilation works
echo "Verifying initial build..."
cd "$PROJECT_DIR"
if su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q"; then
    echo "Initial build successful"
else
    echo "ERROR: Initial build failed!"
    exit 1
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Open project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "library-app" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="