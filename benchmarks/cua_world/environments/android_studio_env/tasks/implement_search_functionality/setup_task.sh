#!/bin/bash
set -e
echo "=== Setting up implement_search_functionality task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Directories
PROJECT_NAME="EmployeeDirectory"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="$PROJECT_DIR/app/src/main/java/com/example/employeedirectory"
RES_DIR="$PROJECT_DIR/app/src/main/res"

# Cleanup previous
rm -rf "$PROJECT_DIR"
mkdir -p "$PACKAGE_DIR"
mkdir -p "$RES_DIR/layout"
mkdir -p "$RES_DIR/values"
mkdir -p "$RES_DIR/menu" # Create menu dir so it's ready/empty or just allow agent to create it

# ------------------------------------------------------------------
# 1. Generate Build Files
# ------------------------------------------------------------------

# settings.gradle.kts
cat > "$PROJECT_DIR/settings.gradle.kts" <<EOF
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
rootProject.name = "$PROJECT_NAME"
include(":app")
EOF

# build.gradle.kts (Project)
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# app/build.gradle.kts
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.employeedirectory"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.employeedirectory"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
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
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}
EOF

# ------------------------------------------------------------------
# 2. Generate Source Code
# ------------------------------------------------------------------

# Employee.kt
cat > "$PACKAGE_DIR/Employee.kt" <<EOF
package com.example.employeedirectory

data class Employee(val id: Int, val name: String, val role: String)
EOF

# EmployeeAdapter.kt (Initial State - No filtering)
cat > "$PACKAGE_DIR/EmployeeAdapter.kt" <<EOF
package com.example.employeedirectory

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class EmployeeAdapter(private var employees: List<Employee>) :
    RecyclerView.Adapter<EmployeeAdapter.EmployeeViewHolder>() {

    class EmployeeViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val nameText: TextView = view.findViewById(R.id.employeeName)
        val roleText: TextView = view.findViewById(R.id.employeeRole)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): EmployeeViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_employee, parent, false)
        return EmployeeViewHolder(view)
    }

    override fun onBindViewHolder(holder: EmployeeViewHolder, position: Int) {
        val employee = employees[position]
        holder.nameText.text = employee.name
        holder.roleText.text = employee.role
    }

    override fun getItemCount() = employees.size
    
    // TODO: Add a function to filter the list based on a query string
}
EOF

# MainActivity.kt
cat > "$PACKAGE_DIR/MainActivity.kt" <<EOF
package com.example.employeedirectory

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import android.view.Menu
import android.view.MenuItem
// import androidx.appcompat.widget.SearchView // Hint: You might need this

class MainActivity : AppCompatActivity() {

    private lateinit var adapter: EmployeeAdapter
    private lateinit var recyclerView: RecyclerView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // Generate dummy data
        val employeeList = listOf(
            Employee(1, "Alice Johnson", "Engineer"),
            Employee(2, "Bob Smith", "Manager"),
            Employee(3, "Charlie Davis", "Designer"),
            Employee(4, "Diana Prince", "Security"),
            Employee(5, "Evan Wright", "Engineer"),
            Employee(6, "Fiona Gallagher", "HR"),
            Employee(7, "George Martin", "Writer"),
            Employee(8, "Hannah Montana", "Artist"),
            Employee(9, "Ian Somerhalder", "Actor"),
            Employee(10, "Julia Roberts", "Director")
        )

        recyclerView = findViewById(R.id.recyclerView)
        recyclerView.layoutManager = LinearLayoutManager(this)
        adapter = EmployeeAdapter(employeeList)
        recyclerView.adapter = adapter
    }

    // TODO: Override onCreateOptionsMenu to inflate the menu and set up the SearchView listener
}
EOF

# ------------------------------------------------------------------
# 3. Generate Resources
# ------------------------------------------------------------------

# AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.EmployeeDirectory"
        tools:targetApi="31">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF

# Dummy xml rules
mkdir -p "$RES_DIR/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$RES_DIR/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$RES_DIR/xml/backup_rules.xml"

# Layouts
cat > "$RES_DIR/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/recyclerView"
        android:layout_width="0dp"
        android:layout_height="0dp"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

cat > "$RES_DIR/layout/item_employee.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="16dp">

    <TextView
        android:id="@+id/employeeName"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textSize="18sp"
        android:textStyle="bold" />

    <TextView
        android:id="@+id/employeeRole"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textSize="14sp"
        android:textColor="#666666" />

</LinearLayout>
EOF

# Strings and Themes
cat > "$RES_DIR/values/strings.xml" <<EOF
<resources>
    <string name="app_name">Employee Directory</string>
    <string name="search_hint">Search employees...</string>
</resources>
EOF

cat > "$RES_DIR/values/themes.xml" <<EOF
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.EmployeeDirectory" parent="Theme.Material3.DayNight.NoActionBar">
        <!-- Customize your light theme here. -->
        <!-- <item name="colorPrimary">@color/my_light_primary</item> -->
    </style>
    <style name="Theme.EmployeeDirectory" parent="Base.Theme.EmployeeDirectory" />
</resources>
EOF

# ------------------------------------------------------------------
# 4. Final Setup
# ------------------------------------------------------------------

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew"

# Record start time
date +%s > /tmp/task_start_time.txt

# Open in Android Studio
setup_android_studio_project "$PROJECT_DIR" "EmployeeDirectory" 120

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="