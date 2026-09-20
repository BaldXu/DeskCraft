package com.deskcraft.desk_craft

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * 数字时钟 widget（M3）。
 *
 * Flutter 侧把 [ClockConfig] 序列化为 JSON 经 home_widget 写入
 * SharedPreferences（key 见 [KEY_CONFIG_JSON]），本 Provider 解析后渲染：
 *
 * - 背景：纯色 / 预置渐变（与 Dart kGradients 一一对应）+ 任意圆角，
 *   绘制成 Bitmap 塞进 widget_bg，与 Flutter 预览逐像素对齐；
 * - 时间：TextClock 零功耗走时（24h "HH:mm" / 12h "a h:mm"）；
 * - 日期 / 星期 / 附加文案：按开关显示隐藏，颜色随文字色分层降透明度。
 */
class ClockWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val config = ClockNativeConfig.from(widgetData.getString(KEY_CONFIG_JSON, null))
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                appWidgetId,
                buildViews(context, appWidgetManager, appWidgetId, config),
            )
        }
    }

    /** 桌面拖拽 / 调整尺寸时按新尺寸重绘背景。 */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    private fun buildViews(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        config: ClockNativeConfig,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.clock_widget)

        // 背景 Bitmap：按当前 widget 实际尺寸绘制，保证圆角不变形
        val size = widgetSizePx(context, appWidgetManager, appWidgetId)
        views.setImageViewBitmap(R.id.widget_bg, buildBackground(context, size[0], size[1], config))

        // 时间：字号 / 颜色 / 走时格式
        views.setTextViewTextSize(
            R.id.widget_time,
            TypedValue.COMPLEX_UNIT_SP,
            config.timeSizeSp.coerceIn(MIN_TIME_SP, MAX_TIME_SP).toFloat(),
        )
        views.setTextColor(R.id.widget_time, config.textColor)
        val timeFormat = if (config.use24h) FORMAT_24H else FORMAT_12H
        // 注意：MIUI 桌面用 HomeMIUIWidgetTextClock 替换 TextClock，
        // setString(String 签名) 反射查不到方法会抛 ActionException 导致整个
        // widget 加载失败，必须用 setCharSequence（CharSequence 签名）。
        views.setCharSequence(R.id.widget_time, "setFormat24Hour", timeFormat)
        views.setCharSequence(R.id.widget_time, "setFormat12Hour", timeFormat)

        // 日期 + 星期：按开关拼格式，全关则隐藏
        val dateFormat = when {
            config.showDate && config.showWeekday -> "M月d日 EEEE"
            config.showDate -> "M月d日"
            config.showWeekday -> "EEEE"
            else -> null
        }
        if (dateFormat == null) {
            views.setViewVisibility(R.id.widget_date, View.GONE)
        } else {
            views.setViewVisibility(R.id.widget_date, View.VISIBLE)
            views.setCharSequence(R.id.widget_date, "setFormat24Hour", dateFormat)
            views.setCharSequence(R.id.widget_date, "setFormat12Hour", dateFormat)
            views.setTextColor(R.id.widget_date, withAlpha(config.textColor, DATE_ALPHA))
        }

        // 附加文案：留空则隐藏
        if (config.extraText.isBlank()) {
            views.setViewVisibility(R.id.widget_extra, View.GONE)
        } else {
            views.setViewVisibility(R.id.widget_extra, View.VISIBLE)
            views.setTextViewText(R.id.widget_extra, config.extraText)
            views.setTextColor(R.id.widget_extra, withAlpha(config.textColor, EXTRA_ALPHA))
        }

        // 点击整个组件回到 App
        views.setOnClickPendingIntent(R.id.widget_root, launchAppPendingIntent(context))
        return views
    }

    /** widget 当前尺寸（px），取自 AppWidgetOptions 的 dp 值换算。 */
    private fun widgetSizePx(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ): IntArray {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val density = context.resources.displayMetrics.density
        // 竖屏语义：MIN_WIDTH = 宽，MAX_HEIGHT = 高；未上报时给保守兜底
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180)
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 80)
        return intArrayOf(
            (widthDp.coerceAtLeast(40) * density).toInt(),
            (heightDp.coerceAtLeast(40) * density).toInt(),
        )
    }

    /** 纯色 / 渐变 + 圆角背景（水平方向，与 Flutter LinearGradient 默认方向一致）。 */
    private fun buildBackground(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        config: ClockNativeConfig,
    ): Bitmap {
        val width = widthPx.coerceIn(1, MAX_BITMAP_PX)
        val height = heightPx.coerceIn(1, MAX_BITMAP_PX)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        when {
            config.bgStyleSolid -> paint.color = config.bgColor
            else -> {
                val colors = GRADIENTS[config.bgGradientIndex.coerceIn(0, GRADIENTS.lastIndex)]
                paint.shader = LinearGradient(
                    0f, 0f, width.toFloat(), 0f,
                    colors[0], colors[1],
                    Shader.TileMode.CLAMP,
                )
            }
        }
        val radius = config.cornerRadiusDp.coerceIn(0, MAX_CORNER_DP) *
            context.resources.displayMetrics.density
        canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), radius, radius, paint)
        return bitmap
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

    companion object {
        /** home_widget 托管 SharedPreferences 里的配置 JSON key（与 ClockConfigStore 对齐）。 */
        const val KEY_CONFIG_JSON = "clock_config_json"

        private const val FORMAT_24H = "HH:mm"
        private const val FORMAT_12H = "a h:mm"
        private const val DATE_ALPHA = 0.78f
        private const val EXTRA_ALPHA = 0.58f
        private const val MIN_TIME_SP = 12
        private const val MAX_TIME_SP = 96
        private const val MAX_CORNER_DP = 48
        private const val MAX_BITMAP_PX = 4096

        /** 与 lib/models/clock_config.dart 的 kGradients 严格一一对应。 */
        private val GRADIENTS = arrayOf(
            intArrayOf(0xFF1A1B2E.toInt(), 0xFF4A3B78.toInt()),
            intArrayOf(0xFF0F2027.toInt(), 0xFF2C5364.toInt()),
            intArrayOf(0xFF2F0743.toInt(), 0xFF41295A.toInt()),
            intArrayOf(0xFF232526.toInt(), 0xFF414345.toInt()),
        )
    }
}

/**
 * 原生侧配置镜像：从 JSON 宽松解析，缺字段 / 解析失败一律回落到
 * 与 Dart [ClockConfig] 构造默认值一致的 [ClockNativeConfig.DEFAULT]。
 */
private data class ClockNativeConfig(
    val textColor: Int,
    val bgStyleSolid: Boolean,
    val bgColor: Int,
    val bgGradientIndex: Int,
    val cornerRadiusDp: Int,
    val timeSizeSp: Int,
    val use24h: Boolean,
    val showDate: Boolean,
    val showWeekday: Boolean,
    val extraText: String,
) {
    companion object {
        val DEFAULT = ClockNativeConfig(
            textColor = 0xFFFFFFFF.toInt(),
            bgStyleSolid = true,
            bgColor = 0xE61C1C22.toInt(),
            bgGradientIndex = 0,
            cornerRadiusDp = 22,
            timeSizeSp = 38,
            use24h = true,
            showDate = true,
            showWeekday = true,
            extraText = "DeskCraft - M1",
        )

        fun from(raw: String?): ClockNativeConfig {
            if (raw.isNullOrBlank()) return DEFAULT
            return try {
                val json = JSONObject(raw)
                ClockNativeConfig(
                    textColor = json.optLong("textColor", DEFAULT.textColor.toLong()).toInt(),
                    bgStyleSolid = json.optString("bgStyle", "solid") != "gradient",
                    bgColor = json.optLong("bgColor", DEFAULT.bgColor.toLong()).toInt(),
                    bgGradientIndex = json.optInt("bgGradientIndex", DEFAULT.bgGradientIndex),
                    cornerRadiusDp = json.optInt("cornerRadiusDp", DEFAULT.cornerRadiusDp),
                    timeSizeSp = json.optInt("timeSizeSp", DEFAULT.timeSizeSp),
                    use24h = json.optBoolean("use24h", DEFAULT.use24h),
                    showDate = json.optBoolean("showDate", DEFAULT.showDate),
                    showWeekday = json.optBoolean("showWeekday", DEFAULT.showWeekday),
                    extraText = json.optString("extraText", DEFAULT.extraText),
                )
            } catch (_: Exception) {
                DEFAULT
            }
        }
    }
}
