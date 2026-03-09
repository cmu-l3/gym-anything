package com.example.expensetracker.services

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Service for displaying budget alert notifications.
 *
 * Currently instantiated manually from Activities.
 * After Hilt migration, inject via constructor with @Inject.
 */
class NotificationService(private val context: Context) {

    companion object {
        private const val CHANNEL_ID = "budget_alerts"
        private const val CHANNEL_NAME = "Budget Alerts"
    }

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Alerts when budget limits are approached"
            }
            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun sendBudgetAlert(category: String, spent: Double, limit: Double) {
        val percentage = (spent / limit * 100).toInt()
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Budget Alert: $category")
            .setContentText("You've used $percentage% of your $category budget")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(category.hashCode(), builder.build())
    }
}
