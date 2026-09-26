package com.deskcraft.desk_craft

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CalendarContract
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 系统日历事件查询（V1 日历组件）。
 *
 * 数据源 = CalendarContract.Instances：用户订阅的节假日源（如小米日历的
 * 「中国节日」）+ 自建重复事件（纪念日等），零维护。
 * 输出按本地日期聚合：{"yyyy-MM-dd": ["标题", ...]}，每格最多保留 5 条去重。
 */
object CalendarEvents {

    /** 每格事件数上限（网格副文字只显示一条，其余留作将来扩展）。 */
    private const val MAX_PER_DAY = 5

    /** 是否已授予 READ_CALENDAR（API 23 前安装即授予，走包级查询）。 */
    fun hasPermission(context: Context): Boolean {
        val permission = android.Manifest.permission.READ_CALENDAR
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        } else {
            context.packageManager.checkPermission(
                permission, context.packageName,
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    /** 某月 [year]/[month]（1-12）的毫秒范围 [起, 止)。 */
    fun monthRangeMillis(year: Int, month: Int): LongArray {
        val cal = Calendar.getInstance()
        cal.clear()
        cal.set(year, month - 1, 1, 0, 0, 0)
        val begin = cal.timeInMillis
        cal.add(Calendar.MONTH, 1)
        return longArrayOf(begin, cal.timeInMillis)
    }

    /**
     * 查询 [beginMillis, endMillis) 内的事件并按本地日期聚合为 JSON。
     * 无权限 / 异常一律返回 "{}"（渲染层回落农历+节气，不阻断刷新链路）。
     */
    fun query(context: Context, beginMillis: Long, endMillis: Long): String {
        if (!hasPermission(context)) return "{}"
        return try {
            val projection = arrayOf(
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.BEGIN,
            )
            val resolver = context.contentResolver
            val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val byDay = LinkedHashMap<String, LinkedHashSet<String>>()
            resolver.query(
                CalendarContract.Instances.CONTENT_URI,
                projection,
                "${CalendarContract.Instances.BEGIN} >= ? AND ${CalendarContract.Instances.BEGIN} < ?",
                arrayOf(beginMillis.toString(), endMillis.toString()),
                "${CalendarContract.Instances.BEGIN} ASC",
            )?.use { cursor ->
                val titleCol = cursor.getColumnIndexOrThrow(CalendarContract.Instances.TITLE)
                val beginCol = cursor.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)
                while (cursor.moveToNext()) {
                    val title = cursor.getString(titleCol)?.trim() ?: continue
                    if (title.isEmpty()) continue
                    val begin = cursor.getLong(beginCol)
                    val day = fmt.format(Date(begin))
                    val set = byDay.getOrPut(day) { LinkedHashSet() }
                    if (set.size < MAX_PER_DAY) set.add(title)
                }
            }
            val json = JSONObject()
            for ((day, titles) in byDay) json.put(day, titles.toList())
            json.toString()
        } catch (_: Exception) {
            "{}"
        }
    }
}
