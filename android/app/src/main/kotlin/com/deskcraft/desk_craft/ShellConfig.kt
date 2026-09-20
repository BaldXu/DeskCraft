package com.deskcraft.desk_craft

import com.topjohnwu.superuser.Shell

/**
 * libsu 全局 Shell 配置的唯一初始化点。
 *
 * [Shell.setDefaultBuilder] 在进程内只允许调用一次（main shell 创建后再调会抛
 * IllegalStateException），而 RootDataSource / MonitorDataSource 会在不同入口
 * （Activity、widget receiver）被独立初始化，必须收敛到这里并保证幂等。
 */
internal object ShellConfig {
    @Volatile
    private var ensured = false

    fun ensure() {
        if (ensured) return
        synchronized(this) {
            if (ensured) return
            Shell.enableVerboseLogging = false
            runCatching {
                Shell.setDefaultBuilder(
                    Shell.Builder.create()
                        .setFlags(Shell.FLAG_REDIRECT_STDERR)
                        .setTimeout(15),
                )
            }
            ensured = true
        }
    }
}
