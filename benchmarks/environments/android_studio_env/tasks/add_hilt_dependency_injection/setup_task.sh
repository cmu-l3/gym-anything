#!/bin/bash
set -e

echo "=== Setting up add_hilt_dependency_injection task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /tmp/task_result.json /tmp/initial_hashes.txt /tmp/build_output.log 2>/dev/null || true

PROJECT_DIR="/home/ga/AndroidStudioProjects/BookTrackerApp"

# Clean up any previous attempt
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/booktracker"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-hdpi"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

echo "Creating project files..."

# === Project-level build.gradle ===
cat > "$PROJECT_DIR/build.gradle" << 'ROOTGRADLE'
plugins {
    id 'com.android.application' version '8.2.2' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.22' apply false
}
ROOTGRADLE

# === settings.gradle ===
cat > "$PROJECT_DIR/settings.gradle" << 'SETTINGS'
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
rootProject.name = "BookTrackerApp"
include ':app'
SETTINGS

# === gradle.properties ===
cat > "$PROJECT_DIR/gradle.properties" << 'GRADLEPROPS'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
GRADLEPROPS

# === local.properties ===
cat > "$PROJECT_DIR/local.properties" << 'LOCALPROPS'
sdk.dir=/opt/android-sdk
LOCALPROPS

# === App-level build.gradle ===
cat > "$PROJECT_DIR/app/build.gradle" << 'APPGRADLE'
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}

android {
    namespace 'com.example.booktracker'
    compileSdk 34

    defaultConfig {
        applicationId "com.example.booktracker"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
        testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = '17'
    }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.11.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    testImplementation 'junit:junit:4.13.2'
    androidTestImplementation 'androidx.test.ext:junit:1.1.5'
    androidTestImplementation 'androidx.test.espresso:espresso-core:3.5.1'
}
APPGRADLE

# === proguard-rules.pro ===
touch "$PROJECT_DIR/app/proguard-rules.pro"

# === AndroidManifest.xml ===
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.BookTrackerApp">
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
MANIFEST

# === Book.kt ===
cat > "$PROJECT_DIR/app/src/main/java/com/example/booktracker/Book.kt" << 'BOOKKT'
package com.example.booktracker

data class Book(
    val id: Int,
    val title: String,
    val author: String,
    val yearPublished: Int,
    val isRead: Boolean = false
)
BOOKKT

# === BookRepository.kt ===
cat > "$PROJECT_DIR/app/src/main/java/com/example/booktracker/BookRepository.kt" << 'REPKT'
package com.example.booktracker

class BookRepository {

    private val books = mutableListOf(
        Book(1, "The Pragmatic Programmer", "David Thomas & Andrew Hunt", 1999, true),
        Book(2, "Clean Code", "Robert C. Martin", 2008, true),
        Book(3, "Design Patterns", "Gang of Four", 1994, false)
    )

    fun getAllBooks(): List<Book> = books.toList()
    fun getReadBooks(): List<Book> = books.filter { it.isRead }
    fun getUnreadBooks(): List<Book> = books.filter { !it.isRead }
}
REPKT

# === MainActivity.kt ===
cat > "$PROJECT_DIR/app/src/main/java/com/example/booktracker/MainActivity.kt" << 'MAINKT'
package com.example.booktracker

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    // TODO: This should be injected via Hilt instead of manual instantiation
    private val bookRepository = BookRepository()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val summaryText = findViewById<TextView>(R.id.summaryText)
        val allBooks = bookRepository.getAllBooks()
        val readCount = bookRepository.getReadBooks().size
        val unreadCount = bookRepository.getUnreadBooks().size

        summaryText.text = "Books: ${allBooks.size} total, $readCount read, $unreadCount unread"
    }
}
MAINKT

# === Resources (Layout, Strings, Colors) ===
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'LAYOUTXML'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <TextView
        android:id="@+id/titleText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/app_name"
        android:textSize="24sp"
        android:textStyle="bold"
        android:layout_marginTop="24dp"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

    <TextView
        android:id="@+id/summaryText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textSize="16sp"
        android:layout_marginTop="16dp"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toBottomOf="@id/titleText"
        tools:text="Books: 3 total, 2 read, 1 unread" />

</androidx.constraintlayout.widget.ConstraintLayout>
LAYOUTXML

cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'STRINGSXML'
<resources>
    <string name="app_name">Book Tracker</string>
</resources>
STRINGSXML

cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'THEMESXML'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.BookTrackerApp" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">@color/purple_500</item>
    </style>
</resources>
THEMESXML

cat > "$PROJECT_DIR/app/src/main/res/values/colors.xml" << 'COLORSXML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="purple_200">#FFBB86FC</color>
    <color name="purple_500">#FF6200EE</color>
    <color name="purple_700">#FF3700B3</color>
    <color name="teal_200">#FF03DAC5</color>
    <color name="teal_700">#FF018786</color>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
</resources>
COLORSXML

# Create valid placeholder icons using Python (1x1 transparent pixel)
python3 -c "
import struct, zlib
def create_png(path):
    # Minimal PNG signature and chunks
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDAT\x08\xd7c\x60\x00\x00\x00\x02\x00\x01\xe2\x21\xbc\x33\x00\x00\x00\x00IEND\xae\x42\x60\x82')
create_png('$PROJECT_DIR/app/src/main/res/mipmap-hdpi/ic_launcher.png')
create_png('$PROJECT_DIR/app/src/main/res/mipmap-hdpi/ic_launcher_round.png')
"

# Set file permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# Setup Gradle Wrapper (copy from system or download)
echo "Setting up Gradle wrapper..."
if [ -f /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew ]; then
    cp /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew "$PROJECT_DIR/gradlew"
    cp /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradle-wrapper.jar "$PROJECT_DIR/gradle/wrapper/"
else
    # Fallback: create dummy wrapper script if missing (should not happen in this env)
    cat > "$PROJECT_DIR/gradlew" << 'GW'
#!/bin/sh
exec gradle "$@"
GW
fi
chmod +x "$PROJECT_DIR/gradlew"
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'GWP'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
GWP

# === Anti-Gaming: Record initial state ===
echo "Recording initial file hashes..."
md5sum "$PROJECT_DIR/build.gradle" > /tmp/initial_hashes.txt
md5sum "$PROJECT_DIR/app/build.gradle" >> /tmp/initial_hashes.txt
md5sum "$PROJECT_DIR/app/src/main/AndroidManifest.xml" >> /tmp/initial_hashes.txt
md5sum "$PROJECT_DIR/app/src/main/java/com/example/booktracker/MainActivity.kt" >> /tmp/initial_hashes.txt
md5sum "$PROJECT_DIR/app/src/main/java/com/example/booktracker/BookRepository.kt" >> /tmp/initial_hashes.txt

# Pre-warm gradle to save time (download distribution)
echo "Pre-warming Gradle..."
su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 ANDROID_SDK_ROOT=/opt/android-sdk ./gradlew --version" > /dev/null 2>&1 || true

# Open Project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "BookTrackerApp" 120

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="