;############################
; description: Generate JUnit-XML output for Yunit-Framework (https://github.com/Uberi/Yunit)
;
; author: hoppfrosch
; date: 20170427
; 本项目适配：修正 AHK v2 Error 对象属性大小写（Line/Message），
;             增加 XML 特殊字符与换行转义，避免生成非法 XML。
;############################
class YunitJUnit{
    ; implemented according http://stackoverflow.com/questions/4922867/junit-xml-format-specification-that-hudson-supports
    __new(instance)
    {
        ; 输出路径：可用静态属性 OutputFile 覆盖（供单测脚本/聚合运行器指定），默认 A_ScriptDir\junit.xml
        if YunitJUnit.HasProp("OutputFile") && YunitJUnit.OutputFile != ""
            this.filename := YunitJUnit.OutputFile
        else
            this.filename := A_ScriptDir . "\junit.xml"
        ; 暴露实例，供测试方读取失败数（this.tests.fail）以决定退出码
        YunitJUnit.Last := this
        ; the file is deleted if it exists already
        if FileExist(this.filename) {
            FileDelete this.filename
        }
        this.out := Array()
        this.tests := {}
        this.tests.pass := 0
        this.tests.fail := 0
        this.tests.overall := 0
    }

    __Delete() {
        ; ExitApp 不触发 __Delete（AHK v2），此处仅兜底；调用方应在 ExitApp 前显式调用 WriteXml()
        try
            this.WriteXml()
    }

    ; 显式写出 JUnit XML。ExitApp 前必须调用，否则文件不落盘。
    WriteXml() {
        ; FileOpen 默认按系统 ANSI 编码写入，必须显式 UTF-8（无 BOM）以匹配 XML 声明
        file := FileOpen(this.filename, "w", "UTF-8-RAW")
        file.write('<?xml version="1.0" encoding="UTF-8"?>`n')
        msg := '<testsuites failures="' . this.tests.fail . '" tests="' . this.tests.overall . '">'
        file.write(msg . "`n")
        msg := '`t<testsuite failures="' . this.tests.fail . '" tests="' . this.tests.overall . '" name="AHK_YUnit">'
        file.write(msg . "`n")
        Loop this.out.Length
            file.write(this.out[A_Index] . "`n")
        file.write("`t</testsuite>`n")
        file.write("</testsuites>`n")
        file.close()
    }

    Update(Category, TestName, Result)
    {
        this.tests.overall := this.tests.overall + 1
        msg := '`t`t<testcase name="' . TestName . '" classname="' . Category . '"'
        if Result is Error
        {
            this.out.Push(msg . ">")
            this.tests.fail := this.tests.fail + 1
            detail := "Line #" Result.Line ": " Result.Message
            detail := YunitJUnit.EscapeXml(detail)
            this.out.Push('`t`t`t<failure message="' . detail . '" type ="failure"></failure>')
            this.out.Push("`t`t</testcase>")
        }
        Else
        {
            this.out.Push(msg . "/>")
            this.tests.pass := this.tests.pass + 1
        }
    }

    ; XML 属性值转义：& < > " ' 以及换行（属性内换行非法）
    static EscapeXml(s) {
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        s := StrReplace(s, '"', "&quot;")
        s := StrReplace(s, "'", "&apos;")
        s := StrReplace(s, "`n", " ")
        s := StrReplace(s, "`r", " ")
        return s
    }
}
