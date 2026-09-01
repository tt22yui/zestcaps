; ==================================================================
; 全局错误处理 —— 未捕获异常 / 运行时错误记录到调试日志
; 依赖：Config（DEBUG_LOG_*）、DebugLog（同目录）
; 用法：在脚本加载阶段 #Include 本文件即可注册 OnError 全局钩子
; ==================================================================
OnError(GlobalErrorHandler)

; 全局未捕获异常 / 运行时错误：记录到日志，返回 1 抑制默认错误对话框（防止模态弹窗
; 阻塞脚本线程造成假死），完整错误信息已写入调试日志，可据此排障
; 注意：
;   1. Mode 在不同场景下可能是 0/1 或字符串（"" / "Exit"），故用 Thrown 类型判断
;   2. 本函数体必须绝对健壮：任何内部异常都会再次触发 OnError 形成递归导致挂起，
;      故整体用 try/catch 兜底，调用栈按类型兼容（标准版 Stack 为数组，个别环境为字符串）
GlobalErrorHandler(Thrown, Mode) {
    try {
        if Thrown is Error {
            err := Thrown
            msg := Format("{1}`n位置: {2}:{3}", err.Message, err.File, err.Line)
            stack := ""
            try {
                st := err.Stack
                if st is Array
                    for f in st
                        stack .= "  " f.What " (" f.File ":" f.Line ")`n"
                else if st is String
                    stack := st
            }
            if stack != ""
                msg .= "`n调用栈:`n" stack
            DebugLog("全局异常[" Mode "]: " msg)
            return 1
        }
        DebugLog("全局错误[" Mode "]: " Thrown)
    }
    catch
        DebugLog("全局异常处理自身出错，已忽略")
    return 1
}
