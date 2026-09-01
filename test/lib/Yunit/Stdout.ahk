class YunitStdOut
{
    __new(instance)
    {
    }
    Update(Category, Test, Result) ;wip: this only supports one level of nesting?
    {
        if Result is Error
        {
            Details := " at line " Result.Line " " Result.Message "(" Result.File ")"
            Status := "FAIL"
        }
        else
        {
            Details := ""
            Status := "PASS"
        }
        ; AHK 为 GUI 程序：无 stdout 管道/重定向时句柄无效，写入会抛 (6) 句柄无效并弹框。
        ; 用 try/catch 静默，无 stdout 时改由 JUnit XML 承载详情；有管道时正常回显。
        try
            FileAppend Status ": " Category "." Test " " Details "`n", "*"
    }
}
