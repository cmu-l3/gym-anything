#!/bin/bash
set -e
echo "=== Setting up Internationalization Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/library-manager"
mkdir -p "$PROJECT_DIR/src/main/java/com/library"
mkdir -p "$PROJECT_DIR/src/main/resources"

# --- 1. Generate POM.xml ---
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.library</groupId>
    <artifactId>library-manager</artifactId>
    <version>1.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
POMEOF

# --- 2. Generate Java Source Files with Hardcoded Strings ---

# Book.java
cat > "$PROJECT_DIR/src/main/java/com/library/Book.java" << 'JAVAEOF'
package com.library;

public class Book {
    private String title;
    private String author;
    private String isbn;
    private int year;

    public Book(String title, String author, String isbn, int year) {
        this.title = title;
        this.author = author;
        this.isbn = isbn;
        this.year = year;
    }

    public String getTitle() { return title; }
    public String getIsbn() { return isbn; }

    @Override
    public String toString() {
        // Hardcoded format string
        return String.format("Title: %s | Author: %s | ISBN: %s | Year: %d", title, author, isbn, year);
    }
}
JAVAEOF

# MenuDisplay.java
cat > "$PROJECT_DIR/src/main/java/com/library/MenuDisplay.java" << 'JAVAEOF'
package com.library;

public class MenuDisplay {
    public void showMenu() {
        System.out.println("\n--- Main Menu ---");
        System.out.println("1. Add a new book");
        System.out.println("2. Search for a book");
        System.out.println("3. List all books");
        System.out.println("4. Remove a book");
        System.out.println("5. Exit");
        System.out.print("Enter your choice: ");
    }
}
JAVAEOF

# LibraryManager.java
cat > "$PROJECT_DIR/src/main/java/com/library/LibraryManager.java" << 'JAVAEOF'
package com.library;

import java.util.ArrayList;
import java.util.List;
import java.util.Scanner;

public class LibraryManager {
    private List<Book> books = new ArrayList<>();
    private Scanner scanner;

    public LibraryManager(Scanner scanner) {
        this.scanner = scanner;
    }

    public void addBook() {
        System.out.print("Enter book title: ");
        String title = scanner.nextLine();
        System.out.print("Enter author name: ");
        String author = scanner.nextLine();
        System.out.print("Enter ISBN: ");
        String isbn = scanner.nextLine();
        System.out.print("Enter publication year: ");
        int year = Integer.parseInt(scanner.nextLine());

        books.add(new Book(title, author, isbn, year));
        System.out.println("Book added successfully!");
    }

    public void searchBook() {
        System.out.print("Enter title to search: ");
        String search = scanner.nextLine();
        boolean found = false;
        for (Book b : books) {
            if (b.getTitle().toLowerCase().contains(search.toLowerCase())) {
                System.out.println(b);
                found = true;
            }
        }
        if (!found) {
            System.out.println("Book not found.");
        }
    }

    public void listBooks() {
        System.out.println("--- Library Catalog ---");
        if (books.isEmpty()) {
            System.out.println("The library is empty.");
        } else {
            for (Book b : books) {
                System.out.println(b);
            }
        }
    }

    public void removeBook() {
        System.out.print("Enter ISBN to remove: ");
        String isbn = scanner.nextLine();
        boolean removed = books.removeIf(b -> b.getIsbn().equals(isbn));
        if (removed) {
            System.out.println("Book removed successfully.");
        } else {
            System.out.println("Error: Book with this ISBN not found.");
        }
    }
}
JAVAEOF

# Main.java
cat > "$PROJECT_DIR/src/main/java/com/library/Main.java" << 'JAVAEOF'
package com.library;

import java.util.Scanner;

public class Main {
    public static void main(String[] args) {
        Scanner scanner = new Scanner(System.in);
        LibraryManager manager = new LibraryManager(scanner);
        MenuDisplay menu = new MenuDisplay();
        boolean running = true;

        System.out.println("=== Welcome to the Library Management System ===");

        while (running) {
            menu.showMenu();
            String choice = scanner.nextLine();

            switch (choice) {
                case "1":
                    manager.addBook();
                    break;
                case "2":
                    manager.searchBook();
                    break;
                case "3":
                    manager.listBooks();
                    break;
                case "4":
                    manager.removeBook();
                    break;
                case "5":
                    running = false;
                    break;
                default:
                    System.out.println("Invalid choice. Please try again.");
            }
        }
        System.out.println("Goodbye! Thank you for using the Library Management System.");
    }
}
JAVAEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# --- 3. Setup IntelliJ ---
# We use the shared setup_intellij_project function which handles
# opening, waiting for indexing, maximizing window, and dismissing dialogs.
setup_intellij_project "$PROJECT_DIR" "library-manager" 120

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="