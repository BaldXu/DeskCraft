package com.deskcraft.desk_craft

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.provider.CalendarContract
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * 日历 widget（V1）：位图路线，原生侧只做极薄壳。
 *
 * - 渲染：Flutter 侧用 CalendarPainter 把整月网格画成 PNG（saveFile 落盘，
 *   路径写入 key [KEY_BITMAP]），本 Provider 只 decodeFile → ImageView；
 * - 数据：系统日历事件（节日/纪念日）由 [CalendarEvents] 按月查询，写入
 *   home_widget 托管 SP（key [KEY_EVENTS]，后台回调经 getWidgetData 读取），
 *   农历/节气由 Dart 侧 lunar 包本地计算，无需权限；
 * - 刷新链路：DATE_CHANGED / TIME_SET / TIMEZONE_CHANGED / 日历数据变更 /
 *   午夜兜底闹钟（[ACTION_REFRESH]）→ 查询事件写 SP → HomeWidgetBackgroundIntent
 *   唤起 headless Flutter 引擎重渲染位图并 updateWidget；
 * - 尺寸：onAppWidgetOptionsChanged 写入实际尺寸（key [KEY_SIZE]），后台回调
 *   按实际尺寸渲染，避免大尺寸拉伸模糊。
 */
class CalendarWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences,
    ) {
        // 秒开：先显示已有位图
        renderAll(context, appWidgetManager, appWidgetIds)
        // 再刷新事件并触发后台重渲染（首次上桌 / 重启兜底）
        refreshAndRerender(context)
    }

    /** 桌面拖拽 / 调整尺寸：写实际尺寸并触发后台按新尺寸重渲染（防模糊）。 */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        writeSize(context, appWidgetId)
        triggerBackground(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val handled = when (intent.action) {
            ACTION_REFRESH -> true
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> true
            // 日历数据变更：只处理 content://com.android.calendar
            Intent.ACTION_PROVIDER_CHANGED ->
                intent.data?.host == CalendarContract.AUTHORITY ||
                    intent.data?.host == "com.android.calendar"
            else -> false
        }
        if (!handled) {
            super.onReceive(context, intent)
            return
        }
        val pending = goAsync()
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, CalendarWidgetProvider::class.java))
        if (ids.isEmpty()) {
            pending.finish()
            return
        }
        // 查询当月事件写 SP → 后台回调重渲染
        writeEvents(context)
        triggerBackground(context)
        scheduleNext(context)
        pending.finish()
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val remaining = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, CalendarWidgetProvider::class.java))
        if (remaining.isEmpty()) cancelAlarm(context)
    }

    // ---- 渲染 ----

    private fun renderAll(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val data = HomeWidgetPlugin.getData(context)
        val bitmapPath = data.getString(KEY_BITMAP, null)
        val bitmap = bitmapPath?.takeIf { it.isNotBlank() }?.let { path ->
            runCatching { BitmapFactory.decodeFile(path) }.getOrNull()
        }
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.calendar_widget)
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.calendar_image, bitmap)
                views.setViewVisibility(R.id.calendar_image, View.VISIBLE)
                views.setViewVisibility(R.id.calendar_fallback, View.GONE)
            } else {
                views.setViewVisibility(R.id.calendar_image, View.GONE)
                views.setViewVisibility(R.id.calendar_fallback, View.VISIBLE)
            }
            views.setOnClickPendingIntent(R.id.calendar_root, launchAppPendingIntent(context))
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    // ---- 数据 / 调度 ----

    /** 刷新事件 → 触发后台重渲染 → 排午夜闹钟（onUpdate / 广播共用）。 */
    private fun refreshAndRerender(context: Context) {
        writeEvents(context)
        triggerBackground(context)
        scheduleNext(context)
    }

    /** 查询当月系统日历事件 → home_widget 托管 SP（后台回调读取）。 */
    private fun writeEvents(context: Context) {
        val now = Calendar.getInstance()
        val range = CalendarEvents.monthRangeMillis(
            now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1,
        )
        val json = CalendarEvents.query(context, range[0], range[1])
        HomeWidgetPlugin.getData(context)
            .edit().putString(KEY_EVENTS, json).apply()
    }

    /** 写当前 widget 实际尺寸（px）到 SP，格式 "WxH"。 */
    private fun writeSize(context: Context, appWidgetId: Int) {
        val manager = AppWidgetManager.getInstance(context)
        val options = manager.getAppWidgetOptions(appWidgetId)
        val density = context.resources.displayMetrics.density
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, REF_WIDTH_DP.toInt())
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, REF_HEIGHT_DP.toInt())
        HomeWidgetPlugin.getData(context)
            .edit()
            .putString(
                KEY_SIZE,
                "${(widthDp.coerceAtLeast(40) * density).toInt()}x" +
                    "${(heightDp.coerceAtLeast(40) * density).toInt()}",
            )
            .apply()
    }

    /** 发 HomeWidgetBackgroundIntent 唤起 headless 引擎重渲染。 */
    private fun triggerBackground(context: Context) {
        try {
            HomeWidgetBackgroundIntent.getBroadcast(context).send()
        } catch (_: Exception) {
            // 后台回调失败不致命：位图维持上一帧，等待下个周期
        }
    }

    /** 午夜兜底闹钟：次日 00:00:03（DATE_CHANGED 可能被 MIUI 延迟）。 */
    private fun scheduleNext(context: Context) {
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_MONTH, 1)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 3)
        cal.set(Calendar.MILLISECOND, 0)
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = refreshPendingIntent(context)
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        if (exact) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
        }
    }

    private fun cancelAlarm(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(refreshPendingIntent(context))
    }

    private fun refreshPendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            RC_REFRESH,
            Intent(context, CalendarWidgetProvider::class.java).setAction(ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

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
        /** home_widget 托管 SharedPreferences key（与 CalendarConfigStore 对齐）。 */
        const val KEY_BITMAP = "calendar_bitmap"
        const val KEY_EVENTS = "calendar_events_json"
        const val KEY_SIZE = "calendar_widget_size"

        private const val ACTION_REFRESH = "com.deskcraft.desk_craft.CALENDAR_REFRESH"
        private const val RC_REFRESH = 2001

        /** 基准 4×4（dp）：与 Dart 侧 CalendarConfigStore.refWidth/HeightDp 对齐。 */
        const val REF_WIDTH_DP = 250f
        const val REF_HEIGHT_DP = 220f
    }
}
