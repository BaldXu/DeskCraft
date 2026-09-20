package com.deskcraft.desk_craft

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.util.Locale

/**
 * 系统监控 widget（M4）。
 *
 * Flutter 侧把 [MonitorConfig] 序列化为 JSON 经 home_widget 写入
 * SharedPreferences（key 见 [KEY_CONFIG_JSON]），本 Provider 解析后渲染：
 *
 * - 背景：与数字时钟同一套 [WidgetBackgroundPainter]（纯色 / 渐变 / 图片 + G2 圆角）；
 * - 数据：[MonitorDataSource.snapshot] 异步采集（root 只读白名单命令 + 电池广播），
 *   每次采样结果缓存到本地（key [KEY_LAST_SNAPSHOT]），重绘时先用缓存秒开再异步刷新；
 * - 调度：AlarmManager 按 [MonitorNativeConfig.refreshIntervalSeconds] 精确闹钟
 *   （ACTION_REFRESH 指回自身 onReceive），Android 12+ 无精确闹钟权限时回落到
 *   setAndAllowWhileIdle（Doze 下系统自动节流）；
 * - 警示：电池温度 ≥ [MonitorNativeConfig.highTempThresholdC] 时温度行变红。
 */
class MonitorWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val config = MonitorNativeConfig.from(widgetData.getString(KEY_CONFIG_JSON, null))
        // 先用缓存快照立即渲染，再异步采新数据
        renderAll(context, appWidgetManager, appWidgetIds, config, cachedSnapshot(context))
        MonitorDataSource.snapshot(context) { data ->
            cacheSnapshot(context, data)
            renderAll(context, appWidgetManager, appWidgetIds, config, data)
            scheduleNext(context, config.refreshIntervalSeconds)
        }
    }

    /** 桌面拖拽 / 调整尺寸时按新尺寸重绘（不打 root 命令，避免拖动期间连发采样）。 */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        val config = MonitorNativeConfig.from(
            HomeWidgetPlugin.getData(context).getString(KEY_CONFIG_JSON, null)
        )
        renderAll(context, appWidgetManager, intArrayOf(appWidgetId), config, cachedSnapshot(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_REFRESH) {
            super.onReceive(context, intent)
            return
        }
        // 定时闹钟触发：采一次数据并重排下一次
        val pending = goAsync()
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, MonitorWidgetProvider::class.java))
        if (ids.isEmpty()) {
            pending.finish()
            return
        }
        val config = MonitorNativeConfig.from(
            HomeWidgetPlugin.getData(context).getString(KEY_CONFIG_JSON, null)
        )
        MonitorDataSource.snapshot(context) { data ->
            cacheSnapshot(context, data)
            renderAll(context, manager, ids, config, data)
            scheduleNext(context, config.refreshIntervalSeconds)
            pending.finish()
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        // 最后一个实例被移除时停掉闹钟
        val remaining = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, MonitorWidgetProvider::class.java))
        if (remaining.isEmpty()) cancelAlarm(context)
    }

    // ---- 渲染 ----

    private fun renderAll(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        config: MonitorNativeConfig,
        data: Map<String, Any?>,
    ) {
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                appWidgetId,
                buildViews(context, appWidgetManager, appWidgetId, config, data),
            )
        }
    }

    private fun buildViews(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        config: MonitorNativeConfig,
        data: Map<String, Any?>,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.monitor_widget)

        // widget 实际尺寸 + 相对默认 4×2 基准的等比缩放系数（与时钟组件同一套逻辑）
        val size = widgetSizePx(context, appWidgetManager, appWidgetId)
        val density = context.resources.displayMetrics.density
        val scale = renderScale(size[0], size[1], density)

        views.setImageViewBitmap(
            R.id.monitor_bg,
            WidgetBackgroundPainter.build(
                context, size[0], size[1],
                config.bgStyle, config.bgColor, config.bgGradientIndex,
                config.bgImagePath, config.cornerRadiusDp, scale,
            ),
        )

        val padH = (H_PADDING_DP * scale * density).toInt()
        val padV = (V_PADDING_DP * scale * density).toInt()
        views.setViewPadding(R.id.monitor_content, padH, padV, padH, padV)

        // 内容块水平对齐：居左 / 居中
        val gravity = if (config.align == "center") {
            Gravity.CENTER_HORIZONTAL or Gravity.CENTER_VERTICAL
        } else {
            Gravity.START or Gravity.CENTER_VERTICAL
        }
        views.setInt(R.id.monitor_content, "setGravity", gravity)

        val tempC = (data["batteryTempC"] as? Number)?.toDouble()
        val cpuUsage = (data["cpuUsagePercent"] as? Number)?.toInt()
        val freqMax = (data["cpuFreqMaxGhz"] as? Number)?.toDouble()
        val freqMin = (data["cpuFreqMinGhz"] as? Number)?.toDouble()
        val memUsage = (data["memUsagePercent"] as? Number)?.toInt()

        // 温度行：超过阈值红色警示
        views.setViewVisibility(R.id.monitor_temp, if (config.showBatteryTemp) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.monitor_temp, "电池 " + (tempC?.let { fmt("%.1f°C", it) } ?: "--"))
        views.setTextColor(
            R.id.monitor_temp,
            if (tempC != null && tempC >= config.highTempThresholdC) WARN_COLOR else config.textColor,
        )
        views.setTextViewTextSize(
            R.id.monitor_temp, TypedValue.COMPLEX_UNIT_SP, (TEMP_SIZE_SP * scale).coerceIn(10f, 48f),
        )

        // CPU 行：占用 + 当前频率（min~max 展示）
        views.setViewVisibility(R.id.monitor_cpu, if (config.showCpu) View.VISIBLE else View.GONE)
        val cpuParts = buildList {
            cpuUsage?.let { add("CPU $it%") }
            freqMax?.let {
                val freqText = if (freqMin != null && freqMin < it) "$it/${trimZero(freqMin)}GHz"
                else "${trimZero(it)}GHz"
                add(freqText)
            }
        }.joinToString(" · ")
        views.setTextViewText(R.id.monitor_cpu, cpuParts.ifEmpty { "CPU --" })
        views.setTextColor(R.id.monitor_cpu, withAlpha(config.textColor, SECONDARY_ALPHA))
        views.setTextViewTextSize(
            R.id.monitor_cpu, TypedValue.COMPLEX_UNIT_SP, (LINE_SIZE_SP * scale).coerceIn(8f, 32f),
        )

        // 内存行
        views.setViewVisibility(R.id.monitor_mem, if (config.showMem) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.monitor_mem, "内存 " + (memUsage?.let { "$it%" } ?: "--"))
        views.setTextColor(R.id.monitor_mem, withAlpha(config.textColor, SECONDARY_ALPHA))
        views.setTextViewTextSize(
            R.id.monitor_mem, TypedValue.COMPLEX_UNIT_SP, (LINE_SIZE_SP * scale).coerceIn(8f, 32f),
        )

        // 异常提示行（无 root / 采样失败）
        val error = data["error"] as? String
        if (error.isNullOrBlank()) {
            views.setViewVisibility(R.id.monitor_note, View.GONE)
        } else {
            views.setViewVisibility(R.id.monitor_note, View.VISIBLE)
            views.setTextViewText(R.id.monitor_note, error)
            views.setTextColor(R.id.monitor_note, withAlpha(config.textColor, NOTE_ALPHA))
            views.setTextViewTextSize(
                R.id.monitor_note, TypedValue.COMPLEX_UNIT_SP, (NOTE_SIZE_SP * scale).coerceIn(7f, 24f),
            )
        }

        // 点击整个组件回到 App
        views.setOnClickPendingIntent(R.id.monitor_root, launchAppPendingIntent(context))
        return views
    }

    // ---- 快照缓存（重绘秒开，不被进程回收打断） ----

    private fun cacheSnapshot(context: Context, data: Map<String, Any?>) {
        val json = JSONObject()
        for ((key, value) in data) if (value != null) json.put(key, value)
        context.getSharedPreferences(DATA_SP, Context.MODE_PRIVATE)
            .edit().putString(KEY_LAST_SNAPSHOT, json.toString()).apply()
    }

    private fun cachedSnapshot(context: Context): Map<String, Any?> {
        val raw = context.getSharedPreferences(DATA_SP, Context.MODE_PRIVATE)
            .getString(KEY_LAST_SNAPSHOT, null) ?: return emptyMap()
        return try {
            val json = JSONObject(raw)
            val out = mutableMapOf<String, Any?>()
            for (key in json.keys()) out[key] = json.opt(key)
            out
        } catch (_: Exception) {
            emptyMap()
        }
    }

    // ---- AlarmManager 调度 ----

    private fun scheduleNext(context: Context, intervalSeconds: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = SystemClock.elapsedRealtime() +
            intervalSeconds.coerceIn(MIN_INTERVAL_S, MAX_INTERVAL_S) * 1000L
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
            Intent(context, MonitorWidgetProvider::class.java).setAction(ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    // ---- 与 ClockWidgetProvider 相同的尺寸自适应工具 ----

    /** widget 当前尺寸（px），取自 AppWidgetOptions 的 dp 值换算。 */
    private fun widgetSizePx(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ): IntArray {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val density = context.resources.displayMetrics.density
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, REF_WIDTH_DP.toInt())
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, REF_HEIGHT_DP.toInt())
        return intArrayOf(
            (widthDp.coerceAtLeast(40) * density).toInt(),
            (heightDp.coerceAtLeast(40) * density).toInt(),
        )
    }

    /** 相对默认 4×2 基准（[REF_WIDTH_DP]×[REF_HEIGHT_DP] dp）的等比缩放系数。 */
    private fun renderScale(widthPx: Int, heightPx: Int, density: Float): Float {
        val widthDp = widthPx / density
        val heightDp = heightPx / density
        val scale = minOf(widthDp / REF_WIDTH_DP, heightDp / REF_HEIGHT_DP)
        return scale.coerceIn(MIN_SCALE, MAX_SCALE)
    }

    private fun withAlpha(color: Int, alpha: Float): Int =
        (color and 0x00FFFFFF) or ((alpha * 255).toInt() shl 24)

    private fun launchAppPendingIntent(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun trimZero(v: Double): String =
        if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()

    /** 固定 US 区域格式化，避免小数点被本地化成逗号。 */
    private fun fmt(pattern: String, vararg args: Any?): String =
        String.format(Locale.US, pattern, *args)

    companion object {
        /** home_widget 托管 SharedPreferences 里的配置 JSON key（与 MonitorConfigStore 对齐）。 */
        const val KEY_CONFIG_JSON = "monitor_config_json"

        private const val ACTION_REFRESH = "com.deskcraft.desk_craft.MONITOR_REFRESH"
        private const val RC_REFRESH = 1001

        /** 与 [MonitorDataSource] 共用的采样数据缓存（快照 JSON）。 */
        private const val DATA_SP = "desk_craft_monitor"
        private const val KEY_LAST_SNAPSHOT = "last_snapshot_json"

        private const val WARN_COLOR = 0xFFFF5252.toInt()
        private const val SECONDARY_ALPHA = 0.78f
        private const val NOTE_ALPHA = 0.58f

        private const val TEMP_SIZE_SP = 17f
        private const val LINE_SIZE_SP = 13f
        private const val NOTE_SIZE_SP = 11f

        private const val REF_WIDTH_DP = 250f
        private const val REF_HEIGHT_DP = 110f
        private const val MIN_SCALE = 0.35f
        private const val MAX_SCALE = 2f

        private const val H_PADDING_DP = 16f
        private const val V_PADDING_DP = 10f

        private const val MIN_INTERVAL_S = 15
        private const val MAX_INTERVAL_S = 3600
    }
}

/**
 * 原生侧配置镜像：从 JSON 宽松解析，缺字段 / 解析失败一律回落到
 * 与 Dart [MonitorConfig] 构造默认值一致的 [MonitorNativeConfig.DEFAULT]。
 */
private data class MonitorNativeConfig(
    val textColor: Int,
    val bgStyle: String,
    val bgColor: Int,
    val bgGradientIndex: Int,
    val bgImagePath: String,
    val cornerRadiusDp: Int,
    val align: String,
    val refreshIntervalSeconds: Int,
    val highTempThresholdC: Double,
    val showBatteryTemp: Boolean,
    val showCpu: Boolean,
    val showMem: Boolean,
) {
    companion object {
        val DEFAULT = MonitorNativeConfig(
            textColor = 0xFFFFFFFF.toInt(),
            bgStyle = "solid",
            bgColor = 0xE61C1C22.toInt(),
            bgGradientIndex = 0,
            bgImagePath = "",
            cornerRadiusDp = 22,
            align = "left",
            refreshIntervalSeconds = 60,
            highTempThresholdC = 45.0,
            showBatteryTemp = true,
            showCpu = true,
            showMem = true,
        )

        fun from(raw: String?): MonitorNativeConfig {
            if (raw.isNullOrBlank()) return DEFAULT
            return try {
                val json = JSONObject(raw)
                MonitorNativeConfig(
                    textColor = json.optLong("textColor", DEFAULT.textColor.toLong()).toInt(),
                    bgStyle = json.optString("bgStyle", "solid"),
                    bgColor = json.optLong("bgColor", DEFAULT.bgColor.toLong()).toInt(),
                    bgGradientIndex = json.optInt("bgGradientIndex", DEFAULT.bgGradientIndex),
                    bgImagePath = json.optString("bgImagePath", DEFAULT.bgImagePath),
                    cornerRadiusDp = json.optInt("cornerRadiusDp", DEFAULT.cornerRadiusDp),
                    align = json.optString("align", DEFAULT.align),
                    refreshIntervalSeconds = json.optInt("refreshIntervalSeconds", DEFAULT.refreshIntervalSeconds),
                    highTempThresholdC = json.optDouble("highTempThresholdC", DEFAULT.highTempThresholdC),
                    showBatteryTemp = json.optBoolean("showBatteryTemp", DEFAULT.showBatteryTemp),
                    showCpu = json.optBoolean("showCpu", DEFAULT.showCpu),
                    showMem = json.optBoolean("showMem", DEFAULT.showMem),
                )
            } catch (_: Exception) {
                DEFAULT
            }
        }
    }
}
