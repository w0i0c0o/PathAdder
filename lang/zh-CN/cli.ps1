# -----------------------------------------------------------------------------
# PathAdder 语言包 - 简体中文 - 分片：cli
#
# 归属模块: PathAdder.ps1 (command line engine)
# 键名约定: Cli.*
# 占位符使用 .NET 复合格式：{0} {1} ...
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- 启动错误 -----------------------------------------------------------
    'Cli.Error.MissingLibrary'  = '缺少公共函数库：{0}'

    # ---- 共用标签 -----------------------------------------------------------
    'Cli.Label.BackupFile'      = '备份文件：{0}'
    'Cli.Label.Directory'       = '目录：{0}'
    'Cli.Label.ErrorDetail'     = '错误信息：{0}'
    'Cli.Label.RestoredFrom'    = '恢复自备份：{0}'
    'Cli.Label.RestoredBackup'  = '本次恢复前的 PATH 已备份为：{0}'

    # ---- 单范围操作结果句 ---------------------------------------------------
    'Cli.Result.NotExecuted'    = '【{0}】未执行。'
    'Cli.Result.Added'          = '已成功添加到【{0}】。'
    'Cli.Result.AlreadyExists'  = '该目录已存在于【{0}】中，未做修改。'
    'Cli.Result.Removed'        = '已成功从【{0}】中移除。'
    'Cli.Result.NotFound'       = '该目录不在【{0}】中，未做修改。'
    'Cli.Result.Failed'         = '操作【{0}】失败：{1}'
    'Cli.Result.Unknown'        = '【{0}】状态未知：{1}'
    'Cli.Result.Success'        = '操作成功。'
    'Cli.Result.NoChange'       = '无需修改。'
    'Cli.Result.Incomplete'     = '操作未完成。'

    # ---- PATH 管理器 --------------------------------------------------------
    'Cli.Manager.NotFound'      = '未找到 PATH 管理器脚本。'
    'Cli.Manager.StartFailed'   = '启动 PATH 管理器失败。'

    # ---- 备份恢复 -----------------------------------------------------------
    'Cli.Restore.MissingBackupFile'    = '恢复备份时缺少 -BackupFile 参数，操作已取消。'
    'Cli.Restore.StillNotAdmin'        = '仍未获得管理员权限，无法恢复【系统 PATH】。'
    'Cli.Restore.ElevationRequested'   = '已请求管理员权限以恢复【系统 PATH】。'
    'Cli.Restore.UacHint'              = '请在 UAC 提示中点击“是”，随后会弹出恢复结果。'
    'Cli.Restore.ElevationFailed'      = '恢复【系统 PATH】需要管理员权限，但提权失败或已被取消。'
    'Cli.Restore.Failed'               = '恢复失败，PATH 未被修改。'
    'Cli.Restore.Succeeded'            = '已恢复【{0}】。'

    # ---- 目标解析 -----------------------------------------------------------
    'Cli.Target.ResolveFailed'  = '无法解析目标文件或目录：'
    'Cli.Target.AddReason'      = '请确认该文件或目录存在，并使用完整的绝对路径（例如 D:\Tools\bin\myapp.exe）。'
    'Cli.Target.RemoveReason'   = '移除操作允许目标已不存在，但仍需提供完整的绝对路径（例如 D:\Tools\bin）。'

    # ---- 单范围操作 ---------------------------------------------------------
    'Cli.Operation.Failed'      = '操作失败，PATH 未被修改。'

    # ---- 系统范围提权 -------------------------------------------------------
    'Cli.System.StillNotAdmin'  = '仍未获得管理员权限，无法修改【系统 PATH】。'
    'Cli.System.AdminHint'      = '请让管理员账户执行此操作，或改用“添加到 PATH（当前用户）”。'
    'Cli.System.ElevationFailed' = '需要管理员权限才能{0}【系统 PATH】，但提权失败或你在 UAC 提示中选择了“否”。'
    'Cli.System.NoAdminHint'    = '如需免管理员操作，请使用“添加到 PATH（当前用户）”。'
    'Cli.Verb.Add'              = '添加'
    'Cli.Verb.Remove'           = '移除'

    # ---- Scope = All 的附加说明 ---------------------------------------------
    'Cli.All.SystemNoAdminNote'           = '（未获得管理员权限，【系统 PATH】未处理。）'
    'Cli.All.SystemElevationRequestedNote' = '（已请求管理员权限处理【系统 PATH】，请在 UAC 提示中点击“是”，随后会有单独的结果提示。）'
    'Cli.All.SystemElevationFailedNote'    = '（【系统 PATH】需要管理员权限，提权失败或已被取消，未作改动。）'

    # ---- 共用收尾提示 -------------------------------------------------------
    'Cli.Msg.PathNotModified'        = 'PATH 未被修改。'
    'Cli.Msg.SystemPathNotModified'  = '系统 PATH 未被修改。'
    'Cli.Msg.NewWindowsHint'         = '新打开的命令行窗口将使用恢复后的 PATH。'
    'Cli.Msg.EffectHint'             = '新打开的命令行窗口（cmd / PowerShell）即可生效；已打开的窗口需重启。'
    'Cli.All.EffectHint'             = '新打开的命令行窗口即可生效；已打开的窗口需重启。'
}
