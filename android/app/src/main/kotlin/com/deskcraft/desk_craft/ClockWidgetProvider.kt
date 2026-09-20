package com.deskcraft.desk_craft

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 数字时钟 widget —— M1 全链路验证组件。
 *
 * 时间/日期由系统 TextClock 驱动（零功耗自动走秒），
 * Flutter 侧 saveWidgetData 写入的数据经 home_widget 存入 SharedPreferences。
 */
class ClockWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val extra = widgetData.getString(KEY_EXTRA_TEXT, null) ?: DEFAULT_EXTRA
        val views = RemoteViews(context.packageName, R.layout.clock_widget).apply {
            setTextViewText(R.id.widget_extra, extra)
            // 点击整个组件回到 App
            setOnClickPendingIntent(R.id.widget_root, launchAppPendingIntent(context))
        }
        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }

    private fun launchAppPendingIntent(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val KEY_EXTRA_TEXT = "clock_extra_text"
        const val DEFAULT_EXTRA = "DeskCraft · M1"
    }
}
