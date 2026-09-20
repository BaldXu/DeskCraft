package com.deskcraft.desk_craft

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * 自定义组件 widget（M6）：Flutter 图层画布渲染的整幅位图上桌。
 *
 * 渲染模型与 monitor/clock 不同——原生侧不做任何布局绘制：
 * - Flutter 侧（编辑器保存 / 后台回调刷新）用 dart:ui 把 [WidgetLayout] 画成 PNG，
 *   经 home_widget saveFile 落盘并把路径写入 key [KEY_BITMAP_PATH]；
 * - 本 Provider 只负责 decodeFile → setImageViewBitmap（fitXY 适配 widget 尺寸）；
 * - 调度：AlarmManager 按 Flutter 写入的 [KEY_REFRESH_SECONDS] 周期触发
 *   [ACTION_REFRESH]，onReceive 里先采样（[MonitorDataSource.snapshot]）把快照
 *   写入 home_widget 托管 SP（key [KEY_VARS_JSON]，后台回调经 loadWidgetVars 读取），
 *   再发 [HomeWidgetBackgroundIntent] 唤起 headless Flutter 引擎重渲染位图并
 *   updateWidget 回写 UI。
 */
class CustomWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences,
    ) {
        renderAll(context, appWidgetManager, appWidgetIds, widgetData.getString(KEY_BITMAP_PATH, null))
        scheduleNext(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_REFRESH) {
            super.onReceive(context, intent)
            return
        }
        val pending = goAsync()
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, CustomWidgetProvider::class.java))
        if (ids.isEmpty()) {
            pending.finish()
            return
        }
        // 先采样写入变量快照，再触发后台回调重渲染，保证回调读到最新数据
        MonitorDataSource.snapshot(context) { data ->
            writeVars(context, data)
            try {
                HomeWidgetBackgroundIntent.getBroadcast(context).send()
            } catch (_: Exception) {
                // 后台回调失败不致命：位图维持上一帧，等待下个周期
            }
            scheduleNext(context)
            pending.finish()
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val remaining = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, CustomWidgetProvider::class.java))
        if (remaining.isEmpty()) cancelAlarm(context)
    }

    // ---- 渲染 ----

    private fun renderAll(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        bitmapPath: String?,
    ) {
        val bitmap = bitmapPath?.takeIf { it.isNotBlank() }?.let { path ->
            runCatching { BitmapFactory.decodeFile(path) }.getOrNull()
        }
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.custom_widget)
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.custom_widget_image, bitmap)
                views.setViewVisibility(R.id.custom_widget_image, View.VISIBLE)
                views.setViewVisibility(R.id.custom_widget_fallback, View.GONE)
            } else {
                views.setViewVisibility(R.id.custom_widget_image, View.GONE)
                views.setViewVisibility(R.id.custom_widget_fallback, View.VISIBLE)
            }
            // 点击整个组件回到 App
            views.setOnClickPendingIntent(R.id.custom_widget_root, launchAppPendingIntent(context))
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    // ---- 快照 → home_widget 托管 SP（后台回调经 HomeWidget.getWidgetData 读取） ----

    private fun writeVars(context: Context, data: Map<String, Any?>) {
        val json = JSONObject()
        for ((key, value) in data) if (value != null) json.put(key, value)
        HomeWidgetPlugin.getData(context)
            .edit().putString(KEY_VARS_JSON, json.toString()).apply()
    }

    // ---- AlarmManager 调度（周期来自 Flutter 侧布局 refreshSeconds） ----

    private fun refreshSeconds(context: Context): Int {
        val raw = HomeWidgetPlugin.getData(context).getInt(KEY_REFRESH_SECONDS, DEFAULT_REFRESH_S)
        return raw.coerceIn(MIN_INTERVAL_S, MAX_INTERVAL_S)
    }

    private fun scheduleNext(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = SystemClock.elapsedRealtime() + refreshSeconds(context) * 1000L
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        if (exact) {
            am.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, refreshPendingIntent(context))
        } else {
            am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, refreshPendingIntent(context))
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
            Intent(context, CustomWidgetProvider::class.java).setAction(ACTION_REFRESH),
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
        /** home_widget 托管 SP 里的位图路径 key（saveFile 内部写入，与 Dart 侧对齐）。 */
        const val KEY_BITMAP_PATH = "custom_widget_bitmap"

        /** 刷新周期（秒），Flutter pushToDesktop 时写入。 */
        const val KEY_REFRESH_SECONDS = "custom_widget_refresh_seconds"

        /** 原生采样快照 JSON，后台回调读作公式变量。 */
        const val KEY_VARS_JSON = "custom_widget_vars_json"

        private const val ACTION_REFRESH = "com.deskcraft.desk_craft.CUSTOM_WIDGET_REFRESH"
        private const val RC_REFRESH = 1002

        private const val DEFAULT_REFRESH_S = 30
        private const val MIN_INTERVAL_S = 1
        private const val MAX_INTERVAL_S = 3600
    }
}
