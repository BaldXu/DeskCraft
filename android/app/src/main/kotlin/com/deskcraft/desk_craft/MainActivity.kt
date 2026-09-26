package com.deskcraft.desk_craft

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /** 日历权限请求的待回执（requestPermission 异步完成时用）。 */
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 启动自执行：预热 root shell（会触发 Magisk 授权弹窗）
        RootDataSource.warmUp()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "probe" -> RootDataSource.probe { data ->
                        runOnUiThread { result.success(data) }
                    }
                    else -> result.notImplemented()
                }
            }
        // 日历桥（CalendarBridge 对应）：权限 / 事件查询 / widget 尺寸
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermission" ->
                        result.success(CalendarEvents.hasPermission(this))
                    "requestPermission" -> requestCalendarPermission(result)
                    "openSettings" -> openCalendarSettings()
                    "queryMonth" -> {
                        val year = call.argument<Int>("year") ?: 1970
                        val month = call.argument<Int>("month") ?: 1
                        val range = CalendarEvents.monthRangeMillis(year, month)
                        result.success(CalendarEvents.query(this, range[0], range[1]))
                    }
                    "widgetSizePx" -> result.success(calendarWidgetSizePx())
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == RC_CALENDAR_PERMISSION) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun requestCalendarPermission(result: MethodChannel.Result) {
        if (CalendarEvents.hasPermission(this)) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(false)
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(android.Manifest.permission.READ_CALENDAR), RC_CALENDAR_PERMISSION)
    }

    private fun openCalendarSettings() {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ),
            )
        } catch (_: Exception) {
            // 跳转失败忽略
        }
    }

    /** 日历 widget 当前尺寸（px）；未上桌返回 null（Flutter 侧回落基准 4×4）。 */
    private fun calendarWidgetSizePx(): List<Int>? {
        val manager = AppWidgetManager.getInstance(this)
        val ids = manager.getAppWidgetIds(
            ComponentName(this, CalendarWidgetProvider::class.java),
        )
        if (ids.isEmpty()) return null
        val options = manager.getAppWidgetOptions(ids.first())
        val density = resources.displayMetrics.density
        val widthDp = options.getInt(
            AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,
            CalendarWidgetProvider.REF_WIDTH_DP.toInt(),
        )
        val heightDp = options.getInt(
            AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT,
            CalendarWidgetProvider.REF_HEIGHT_DP.toInt(),
        )
        return listOf(
            (widthDp.coerceAtLeast(40) * density).toInt(),
            (heightDp.coerceAtLeast(40) * density).toInt(),
        )
    }

    companion object {
        const val CHANNEL = "desk_craft/root"
        const val CALENDAR_CHANNEL = "desk_craft/calendar"
        private const val RC_CALENDAR_PERMISSION = 3001
    }
}
