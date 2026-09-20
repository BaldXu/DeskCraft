package com.deskcraft.desk_craft

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.util.Log
import com.topjohnwu.superuser.Shell

/**
 * 系统监控数据源（M4）。
 *
 * - CPU 频率 / CPU 占用 / 内存：root 只读白名单命令（libsu）；
 * - 电池温度：系统 sticky 广播 ACTION_BATTERY_CHANGED，无需 root；
 * - CPU 占用：/proc/stat 首行两次采样差值，上次采样持久化在
 *   [SP_NAME]（进程被杀重启后仍能正确计算）。
 *
 * 约定同 [RootDataSource]：只执行 [WHITELIST] 固定字符串命令，
 * 禁止拼接外部输入，禁止写操作。
 */
object MonitorDataSource {

    private const val TAG = "DeskCraftMonitor"

    // ---- 白名单命令（固定字符串，只读）----

    private const val CMD_CPU_USAGE = "cat /proc/stat | head -1"
    private const val CMD_MEM = "cat /proc/meminfo | head -5"
    private const val CMD_CPU_FREQ =
        "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq"

    private val WHITELIST = listOf(CMD_CPU_USAGE, CMD_MEM, CMD_CPU_FREQ)

    init {
        ShellConfig.ensure()
    }

    // ---- /proc/stat 采样持久化 ----

    private const val SP_NAME = "desk_craft_monitor"
    private const val SP_KEY_LAST_STAT = "last_cpu_stat"

    /**
     * 采集一次监控快照，回调可跨线程传输的 Map：
     * rooted / batteryTempC / cpuUsagePercent / memUsagePercent /
     * cpuFreqMaxGhz / cpuFreqMinGhz / error（数值项解析失败可缺省）。
     */
    fun snapshot(context: Context, onResult: (Map<String, Any?>) -> Unit) {
        val batteryTempC = readBatteryTempC(context)
        Shell.getShell { shell ->
            if (!shell.isRoot) {
                onResult(
                    mapOf(
                        "rooted" to false,
                        "batteryTempC" to batteryTempC,
                        "error" to "无 root：CPU / 内存指标不可用",
                    )
                )
                return@getShell
            }
            Shell.cmd(CMD_CPU_USAGE).submit { statResult ->
                Shell.cmd(CMD_MEM).submit { memResult ->
                    Shell.cmd(CMD_CPU_FREQ).submit { freqResult ->
                        val data = mutableMapOf<String, Any?>(
                            "rooted" to true,
                            "batteryTempC" to batteryTempC,
                        )
                        data["cpuUsagePercent"] =
                            cpuUsagePercent(context, statResult.out.firstOrNull())
                        parseMemInfo(memResult.out)?.let { mem ->
                            val total = mem["MemTotal"]
                            val avail = mem["MemAvailable"] ?: mem["MemFree"]
                            if (total != null && total > 0 && avail != null && avail in 0..total) {
                                data["memUsagePercent"] =
                                    (((total - avail) * 100 + total / 2) / total).toInt()
                            }
                        }
                        val freqs = freqResult.out.mapNotNull { it.trim().toLongOrNull() }
                        if (freqs.isNotEmpty()) {
                            data["cpuFreqMaxGhz"] = round2(freqs.max() / 1_000_000.0)
                            data["cpuFreqMinGhz"] = round2(freqs.min() / 1_000_000.0)
                        }
                        data["error"] = collectError(statResult, memResult, freqResult)
                        onResult(data)
                    }
                }
            }
        }
    }

    /** 电池温度（°C）：sticky 广播，无需 root；拿不到返回 null。 */
    private fun readBatteryTempC(context: Context): Double? {
        return try {
            val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                ?: return null
            val deci = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
            if (deci == Int.MIN_VALUE) null else deci / 10.0
        } catch (e: Exception) {
            Log.w(TAG, "readBatteryTempC failed", e)
            null
        }
    }

    /**
     * 解析 /proc/stat 首行并和上次采样做差值计算占用率（0~100）。
     * 首次运行 / 解析失败 / 增量为 0 时返回 null（本次先落盘采样）。
     */
    private fun cpuUsagePercent(context: Context, line: String?): Int? {
        if (line == null || !line.startsWith("cpu ")) return null
        val fields = line.trim().split(Regex("\\s+")).drop(1).map { it.toLongOrNull() ?: 0L }
        // user nice system idle iowait irq softirq steal ...
        if (fields.size < 5) return null
        val idle = fields[3] + fields[4]
        val total = fields.sum()
        val sp = context.getSharedPreferences(SP_NAME, Context.MODE_PRIVATE)
        val last = sp.getString(SP_KEY_LAST_STAT, null)
            ?.split(',')?.mapNotNull { it.toLongOrNull() }
        sp.edit().putString(SP_KEY_LAST_STAT, "$total,$idle").apply()
        if (last == null || last.size != 2) return null
        val dTotal = total - last[0]
        val dIdle = idle - last[1]
        if (dTotal <= 0 || dIdle < 0) return null
        return (((dTotal - dIdle) * 100 + dTotal / 2) / dTotal).toInt().coerceIn(0, 100)
    }

    private fun round2(v: Double) = (v * 100).toInt() / 100.0

    /** "MemTotal:  11843888 kB" → {MemTotal: 11843888, ...}；失败返回 null。 */
    private fun parseMemInfo(lines: List<String>): Map<String, Long>? {
        val info = mutableMapOf<String, Long>()
        for (line in lines) {
            val idx = line.indexOf(':')
            if (idx <= 0) continue
            val value = line.substring(idx + 1).trim().split(' ').firstOrNull()
                ?.toLongOrNull() ?: continue
            info[line.substring(0, idx).trim()] = value
        }
        return if (info.isEmpty()) null else info
    }

    private fun collectError(vararg results: Shell.Result): String? =
        results.firstOrNull { !it.isSuccess }?.err?.joinToString("\n") { it }
}
