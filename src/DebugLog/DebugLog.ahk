; ==================================================================
; 调试日志实现 —— 用于排查按键卡死等问题
; 配置项（DEBUG_LOG_ENABLED / FILE / MAX_SIZE_KB）在 config.ahk 中
; ==================================================================

; 确保日志目录存在：FileAppend 不会自动创建目录（文档要求目标目录已存在），
; 首次运行前先建好，避免新环境日志静默写入失败
SplitPath DEBUG_LOG_FILE, , &logDir
if logDir != "" && !DirExist(logDir)
    DirCreate(logDir)

DebugLog(msg) {
    global DEBUG_LOG_ENABLED, DEBUG_LOG_FILE, DEBUG_LOG_MAX_SIZE_KB
    static writeCount := 0
    if !DEBUG_LOG_ENABLED
        return
    try {
        ; 毫秒级时间戳（A_MSec 取当前毫秒并补零三位），用于定位启动/退出时序瓶颈
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss") "." SubStr("000" A_MSec, -3)
        line := "[" timestamp "] " msg "`n"
        FileAppend(line, DEBUG_LOG_FILE, "UTF-8")

        ; 每 100 次写入才检查一次大小，降低系统调用频率
        if (++writeCount < 100)
            return
        writeCount := 0

        ; 超限轮转：把当前文件改名 .old，保留最近一段，而不是整体清空
        if (FileGetSize(DEBUG_LOG_FILE) > DEBUG_LOG_MAX_SIZE_KB * 1024)
            FileMove(DEBUG_LOG_FILE, DEBUG_LOG_FILE ".old", 1)
    }
}
; ==================================================================
