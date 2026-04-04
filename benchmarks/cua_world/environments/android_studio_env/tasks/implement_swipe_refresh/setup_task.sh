#!/bin/bash
set -e
echo "=== Setting up implement_swipe_refresh task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="BookStream"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"

# Clean up previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Create Project Directories
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/bookstream"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/assets"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# --- Write Gradle Files ---
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

cat > "$PROJECT_DIR/settings.gradle.kts" << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "BookStream"
include(":app")
EOF

cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.bookstream"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.bookstream"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.7.0")
    implementation("androidx.activity:activity-ktx:1.8.2")
    // TODO: Add SwipeRefreshLayout dependency here
}
EOF

# --- Write Real Data (books.json) ---
cat > "$PROJECT_DIR/app/src/main/assets/books.json" << 'EOF'
[
  {"id": 1, "title": "Pride and Prejudice", "author": "Jane Austen", "year": 1813},
  {"id": 2, "title": "Moby Dick", "author": "Herman Melville", "year": 1851},
  {"id": 3, "title": "Great Expectations", "author": "Charles Dickens", "year": 1861},
  {"id": 4, "title": "The Adventures of Huckleberry Finn", "author": "Mark Twain", "year": 1884},
  {"id": 5, "title": "The Great Gatsby", "author": "F. Scott Fitzgerald", "year": 1925},
  {"id": 6, "title": "War and Peace", "author": "Leo Tolstoy", "year": 1869},
  {"id": 7, "title": "The Catcher in the Rye", "author": "J.D. Salinger", "year": 1951},
  {"id": 8, "title": "To Kill a Mockingbird", "author": "Harper Lee", "year": 1960},
  {"id": 9, "title": "1984", "author": "George Orwell", "year": 1949},
  {"id": 10, "title": "Ulysses", "author": "James Joyce", "year": 1922}
]
EOF

# --- Write Kotlin Source Files ---

# Book.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/bookstream/Book.kt" << 'EOF'
package com.example.bookstream

data class Book(
    val id: Int,
    val title: String,
    val author: String,
    val year: Int
)
EOF

# BooksAdapter.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/bookstream/BooksAdapter.kt" << 'EOF'
package com.example.bookstream

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView

class BooksAdapter : ListAdapter<Book, BooksAdapter.BookViewHolder>(BookDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): BookViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(android.R.layout.simple_list_item_2, parent, false)
        return BookViewHolder(view)
    }

    override fun onBindViewHolder(holder: BookViewHolder, position: Int) {
        val book = getItem(position)
        holder.bind(book)
    }

    class BookViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val titleView: TextView = itemView.findViewById(android.R.id.text1)
        private val subtitleView: TextView = itemView.findViewById(android.R.id.text2)

        fun bind(book: Book) {
            titleView.text = book.title
            subtitleView.text = "${book.author} (${book.year})"
        }
    }

    class BookDiffCallback : DiffUtil.ItemCallback<Book>() {
        override fun areItemsTheSame(oldItem: Book, newItem: Book): Boolean = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: Book, newItem: Book): Boolean = oldItem == newItem
    }
}
EOF

# MainViewModel.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/bookstream/MainViewModel.kt" << 'EOF'
package com.example.bookstream

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.InputStreamReader

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val _books = MutableLiveData<List<Book>>()
    val books: LiveData<List<Book>> = _books

    init {
        loadBooks()
    }

    private fun loadBooks() {
        try {
            val inputStream = getApplication<Application>().assets.open("books.json")
            val reader = InputStreamReader(inputStream)
            val type = object : TypeToken<List<Book>>() {}.type
            val bookList: List<Book> = Gson().fromJson(reader, type)
            _books.value = bookList
        } catch (e: Exception) {
            e.printStackTrace()
            _books.value = emptyList()
        }
    }

    fun refreshData() {
        // Simulate a network refresh by just reloading the data
        loadBooks()
    }
}
EOF

# MainActivity.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/bookstream/MainActivity.kt" << 'EOF'
package com.example.bookstream

import android.os.Bundle
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
// TODO: Import SwipeRefreshLayout

class MainActivity : AppCompatActivity() {

    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val recyclerView = findViewById<RecyclerView>(R.id.recycler_view)
        val adapter = BooksAdapter()
        
        recyclerView.layoutManager = LinearLayoutManager(this)
        recyclerView.adapter = adapter

        viewModel.books.observe(this) { books ->
            adapter.submitList(books)
        }

        // TODO: Initialize SwipeRefreshLayout and set OnRefreshListener
    }
}
EOF

# --- Write Layout Resources ---
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/recycler_view"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintBottom_toBottomOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">BookStream</string>
</resources>
EOF

# --- Finalize Setup ---
# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# Initialize Gradle wrapper
cd "$PROJECT_DIR"
gradle wrapper --gradle-version 8.4 > /dev/null 2>&1 || true
chmod +x gradlew

# Open Android Studio
setup_android_studio_project "$PROJECT_DIR" "BookStream" 180

# Capture initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="