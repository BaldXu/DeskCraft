package com.deskcraft.desk_craft

import android.os.SystemClock
import android.util.Log
import com.topjohnwu.superuser.Shell

/**
 * Root 数据源 —— M2 验证：libsu 执行白名单只读命令，读取 sysfs 温度 / CPU 频率。
 *
 * 约定：本类只允许执行 [WHITELIST] 中列出的固定命令字符串，
 * 禁止拼接任何外部输入，禁止写操作。
 */
object RootDataSource {

    private const val TAG = "DeskCraftRoot"

    init {
        ShellConfig.ensure()
    }

    // ---- 白名单命令（固定字符串，只读）----

    private const val CMD_CPU_FREQ =
        "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq"

    private const val CMD_THERMAL =
        "for z in /sys/class/thermal/thermal_zone*; do " +
            "echo \"\$(basename \$z)|\$(cat \$z/type)|\$(cat \$z/temp)\"; done"

    private const val CMD_MEM =
        "cat /proc/meminfo | head -5"

    private val WHITELIST = listOf(CMD_CPU_FREQ, CMD_THERMAL, CMD_MEM)

    /**
     * 预热主 root shell（App 启动即调用，触发 Magisk 授权弹窗）。
     */
    fun warmUp() {
        Shell.getShell { shell ->
            Log.i(TAG, "main shell ready, isRoot=${shell.isRoot}")
        }
    }

    /**
     * 执行白名单命令并解析，回调一个可跨 MethodChannel 传输的 Map。
     */
    fun probe(onResult: (Map<String, Any?>) -> Unit) {
        val startAt = SystemClock.elapsedRealtime()

        Shell.getShell { shell ->
            if (!shell.isRoot) {
                onResult(
                    baseResult(false, startAt, error = "无 root：libsu 只拿到了非特权 shell")
                )
                return@getShell
            }

            Shell.cmd(CMD_CPU_FREQ).submit { freqResult ->
                Shell.cmd(CMD_THERMAL).submit { thermalResult ->
                    Shell.cmd(CMD_MEM).submit { memResult ->
                        val data = baseResult(true, startAt).toMutableMap()
                        data["cpuFreqsKHz"] = parseCpuFreqs(freqResult.out)
                        data["thermalZones"] = parseThermal(thermalResult.out)
                        data["memInfoKb"] = parseMemInfo(memResult.out)
                        data["error"] = collectError(freqResult, thermalResult, memResult)
                        onResult(data)
                    }
                }
            }
        }
    }

    private fun baseResult(rooted: Boolean, startAt: Long, error: String? = null) =
        mapOf(
            "rooted" to rooted,
            "tookMs" to (SystemClock.elapsedRealtime() - startAt),
            "error" to error,
        )

    // ---- 解析 ----

    /** 每核当前频率（kHz），顺序即 cpu0..cpuN。 */
    private fun parseCpuFreqs(lines: List<String>): List<Long> =
        lines.mapNotNull { it.trim().toLongOrNull() }

    /** "thermal_zone0|cpu0|36500" → {name, type, tempMilli}。 */
    private fun parseThermal(lines: List<String>): List<Map<String, Any?>> =
        lines.mapNotNull { line ->
            val parts = line.split('|')
            if (parts.size < 3) return@mapNotNull null
            val name = parts[0].trim()
            val type = parts[1].trim()
            val tempMilli = parts[2].trim().toLongOrNull() ?: return@mapNotNull null
            mapOf("name" to name, "type" to type, "tempMilli" to tempMilli)
        }

    /** "MemTotal:  11843888 kB" → {MemTotal: 11843888, ...}。 */
    private fun parseMemInfo(lines: List<String>): Map<String, Long> {
        val info = mutableMapOf<String, Long>()
        for (line in lines) {
            val idx = line.indexOf(':')
            if (idx <= 0) continue
            val value = line.substring(idx + 1).trim().split(' ').firstOrNull()
                ?.toLongOrNull() ?: continue
            info[line.substring(0, idx).trim()] = value
        }
        return info
    }

    private fun collectError(vararg results: Shell.Result): String? =
        results.firstOrNull { !it.isSuccess }?.err?.joinToString("\n") { it }
}
