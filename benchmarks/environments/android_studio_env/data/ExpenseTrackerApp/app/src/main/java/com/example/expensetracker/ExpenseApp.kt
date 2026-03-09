package com.example.expensetracker

import android.app.Application

/**
 * Application class for ExpenseTrackerApp.
 *
 * NOTE: This class currently has no dependency injection framework.
 * All dependencies are created manually in each Activity.
 * A Hilt migration would add the appropriate application-level DI annotation.
 */
class ExpenseApp : Application() {

    override fun onCreate() {
        super.onCreate()
        // Initialize any app-level singletons here
    }
}
