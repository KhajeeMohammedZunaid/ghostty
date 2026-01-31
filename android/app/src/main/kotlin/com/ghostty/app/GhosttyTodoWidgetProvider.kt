package com.ghostty.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.widget.RemoteViews
import android.view.View
import android.graphics.Paint
import android.os.Build

class GhosttyTodoWidgetProvider : AppWidgetProvider() {

    companion object {
        private val todoRowIds = intArrayOf(
            R.id.todo_row_1,
            R.id.todo_row_2,
            R.id.todo_row_3,
            R.id.todo_row_4,
            R.id.todo_row_5
        )

        private val todoItemIds = intArrayOf(
            R.id.todo_item_1,
            R.id.todo_item_2,
            R.id.todo_item_3,
            R.id.todo_item_4,
            R.id.todo_item_5
        )

        private val todoCheckIds = intArrayOf(
            R.id.todo_check_1,
            R.id.todo_check_2,
            R.id.todo_check_3,
            R.id.todo_check_4,
            R.id.todo_check_5
        )

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.ghostty_widget_layout)
            
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            
            val todoTitles = prefs.getString("todo_titles", "") ?: ""
            val todoIds = prefs.getString("todo_ids", "") ?: ""
            val todoCompleted = prefs.getString("todo_completed", "") ?: ""
            val todoCount = prefs.getString("todo_count", "0") ?: "0"
            
            val countInt = todoCount.toIntOrNull() ?: 0
            views.setTextViewText(R.id.todo_count, if (countInt == 0) "All done!" else "$todoCount pending")
            
            val titles = if (todoTitles.isNotEmpty()) todoTitles.split("|||") else emptyList()
            val ids = if (todoIds.isNotEmpty()) todoIds.split("|||") else emptyList()
            val completed = if (todoCompleted.isNotEmpty()) todoCompleted.split("|||") else emptyList()
            
            for (rowId in todoRowIds) {
                views.setViewVisibility(rowId, View.GONE)
            }
            
            if (titles.isEmpty()) {
                views.setViewVisibility(R.id.empty_message, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.empty_message, View.GONE)
                
                for (i in titles.indices) {
                    if (i < todoRowIds.size && i < ids.size) {
                        views.setViewVisibility(todoRowIds[i], View.VISIBLE)
                        
                        val isCompleted = i < completed.size && completed[i] == "1"
                        
                        views.setTextViewText(todoItemIds[i], titles[i])
                        
                        if (isCompleted) {
                            views.setTextColor(todoItemIds[i], android.graphics.Color.parseColor("#888888"))
                            views.setInt(todoItemIds[i], "setPaintFlags", Paint.STRIKE_THRU_TEXT_FLAG or Paint.ANTI_ALIAS_FLAG)
                            views.setImageViewResource(todoCheckIds[i], R.drawable.widget_checkbox_checked)
                        } else {
                            views.setTextColor(todoItemIds[i], android.graphics.Color.WHITE)
                            views.setInt(todoItemIds[i], "setPaintFlags", Paint.ANTI_ALIAS_FLAG)
                            views.setImageViewResource(todoCheckIds[i], R.drawable.widget_checkbox_unchecked)
                        }
                    }
                }
            }
            
            val addTodoIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                action = "OPEN_TODO_EDITOR"
            }
            val addPendingIntent = PendingIntent.getActivity(
                context,
                100,
                addTodoIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.add_todo_button, addPendingIntent)
            
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, GhosttyTodoWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            
            for (appWidgetId in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }
    }

    override fun onEnabled(context: Context) {}

    override fun onDisabled(context: Context) {}
}
