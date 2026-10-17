# -----------------------------------------------------------------------------
# PathAdder 语言包 - 简体中文 - 分片：core
#
# 归属模块：lib\Common.ps1（公共库）+ 全项目共用键
# 键名约定：App.* / Core.*
# 占位符使用 .NET 复合格式：{0} {1} ...
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- 应用标识 -------------------------------------------------------
    'App.Name'              = 'PATH 助手'
    'App.Language.en-US'    = 'English'
    'App.Language.zh-CN'    = '简体中文'

    # ---- 通用按钮 / 标签 ------------------------------------------------
    'App.Button.OK'         = '确定'
    'App.Button.Cancel'     = '取消'
    'App.Button.Close'      = '关闭'
    'App.Button.Yes'        = '是'
    'App.Button.No'         = '否'
    'App.Button.Refresh'    = '刷新'
    'App.Button.Browse'     = '浏览...'
    'App.Button.Apply'      = '应用'
    'App.Button.Delete'     = '删除'
    'App.Button.Restore'    = '恢复'
    'App.Button.Backup'     = '备份'
    'App.Button.Export'     = '导出'
    'App.Button.Open'       = '打开'
    'App.Button.Help'       = '帮助'
    'App.Language'          = '语言'

    # ---- 作用范围 -------------------------------------------------------
    'App.Scope.User'        = '用户级'
    'App.Scope.System'      = '系统级（所有用户）'
    'App.Scope.All'         = '用户级 + 系统级'

    # ---- 操作状态 -------------------------------------------------------
    'App.Status.Added'      = '已添加'
    'App.Status.Removed'    = '已移除'
    'App.Status.AlreadyExists' = '已存在'
    'App.Status.NotFound'   = '未找到'
    'App.Status.Failed'     = '失败'
    'App.Status.Skipped'    = '已跳过'

    # ---- 共用提示 -------------------------------------------------------
    'App.Msg.AdminRequired' = '该操作需要管理员权限。'
    'App.Msg.UacCancelled'  = '提权被取消或拒绝，未做任何修改。'
    'App.Msg.UnknownError'  = '未知错误。'
    'App.Msg.OperationCancelled' = '操作已取消。'

    # ---- 公共库错误 / 警告（lib\Common.ps1）------------------------------
    'Core.Err.RegistryKeyOpenFailed'    = '无法打开注册表键（不存在或无读取权限）。'
    'Core.Err.RegistryWriteOpenFailed'  = '打开注册表写入失败（需要管理员权限？）：{0}'
    'Core.Err.RegistryWriteHandleFailed' = '打开注册表写入失败：无法获取 {0} 级 Environment 键的可写句柄。'
    'Core.Err.BackupFileNotFound'       = '备份文件不存在：{0}'
    'Core.Warn.UnknownPathValueKind'    = 'PATH 值类型为未知或非字符串型（{0}），本工具只处理字符串型。已回退为 ExpandString，请人工确认 PATH 内容无误后再继续使用。'

    # ---- 添加 / 移除结果（lib\Common.ps1）--------------------------------
    'Core.Msg.Add.DirEmpty'      = '目录为空，无法添加。'
    'Core.Msg.Add.InvalidDir'    = '目录路径无效（必须是一个可用的绝对路径）：{0}'
    'Core.Msg.Remove.DirEmpty'   = '目录为空，无法移除。'
    'Core.Msg.Remove.InvalidDir' = '目录路径无效（必须是一个绝对路径）：{0}'
    'Core.Msg.DirNotFound'       = '目录不存在：{0}'
    'Core.Msg.ReadPathFailed'    = '读取 PATH 失败：{0}'
    'Core.Msg.WritePathFailed'   = '写入 PATH 失败（已保留备份 {0}）：{1}'
    'Core.Msg.Add.AlreadyExists' = '该目录已存在于 PATH 中，未做修改。'
    'Core.Msg.Remove.NotFound'   = '该目录不在 PATH 中，未做修改。'
    'Core.Msg.Added'             = '已添加到 PATH。'
    'Core.Msg.Removed'           = '已从 PATH 中移除。'

    # ---- 变更日志字段名（lib\Common.ps1）---------------------------------
    'Core.Log.Label.Action'      = '动作='
    'Core.Log.Label.Scope'       = '范围='
    'Core.Log.Label.Directory'   = '目录='
    'Core.Log.Label.Backup'      = '备份='
    'Core.Log.Label.Kind'        = '类型='
    'Core.Log.RestoreFrom'       = '恢复自 {0}'
}
