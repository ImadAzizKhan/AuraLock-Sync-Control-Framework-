package com.example.locket_boss

import io.flutter.embedding.android.FlutterActivity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class AppWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                
                // 💖 HEART BUTTON CLICK LOGIC (Wakes app with amore://heart)
                val heartIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("amore://heart"))
                setOnClickPendingIntent(R.id.btn_heart, heartIntent)

                // ⚠️ DANGER BUTTON CLICK LOGIC (Wakes app with amore://danger)
                val dangerIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("amore://danger"))
                setOnClickPendingIntent(R.id.btn_danger, dangerIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

class MainActivity : FlutterActivity()
