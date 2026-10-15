# -----------------------------------------------------------------------------
# PathAdder 语言包 - 简体中文 - shard: gui
#
# 归属模块: PathManager.ps1 (WinForms GUI)
# 键名约定: Mgr.*
# 占位符使用 .NET 复合格式：{0} {1} ...
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- 窗体标题 -------------------------------------------------------
    'Mgr.Title'                 = 'PATH 管理器'
    'Mgr.Title.StartupFailed'   = 'PATH 助手 - 启动失败'
    'Mgr.Title.BackupPreview'   = '备份预览 - {0}'

    # ---- PATH 列表分组 --------------------------------------------------
    'Mgr.Group.UserPath'        = '用户 PATH (HKCU\Environment)'
    'Mgr.Group.SystemPath'      = '系统 PATH (HKLM\...\Session Manager\Environment)'

    # ---- 通用界面文本 ---------------------------------------------------
    'Mgr.Text.EntryCount'       = '（共 {0} 项）'
    'Mgr.Text.EmptyPath'        = '（该 PATH 为空）'
    'Mgr.Text.ReadFailed'       = '（读取失败：{0}）'

    # ---- 标签页 ---------------------------------------------------------
    'Mgr.Tab.Backups'           = '备份历史'
    'Mgr.Tab.Log'               = '变更日志'

    # ---- 备份列表列头 ---------------------------------------------------
    'Mgr.Column.File'           = '备份文件'
    'Mgr.Column.Scope'          = '范围'
    'Mgr.Column.Time'           = '时间'
    'Mgr.Column.Size'           = '大小(字节)'
    'Mgr.Column.Path'           = '完整路径'

    # ---- 按钮 -----------------------------------------------------------
    'Mgr.Button.OpenBackupDir'  = '打开备份目录'
    'Mgr.Button.OpenLog'        = '打开变更日志'
    'Mgr.Button.Preview'        = '预览内容'
    'Mgr.Button.RestoreToBackup' = '恢复到此次备份'
    'Mgr.Button.RefreshBackups' = '刷新备份列表'

    # ---- 提示 / 表头 ----------------------------------------------------
    'Mgr.Hint'                  = '提示：修改【系统 PATH】需要管理员权限；任何修改前都会自动备份，可随时在“备份历史”中恢复。'
    'Mgr.Log.Header'            = '最近 {0} 条（倒序，最新在最上方）  日志格式：[时间] 动作=… 范围=… 目录=… 备份=… 类型=…'
    'Mgr.Log.Empty'             = '（暂无变更日志。执行过添加/移除/恢复操作后，这里会显示记录。）'

    # ---- 状态栏 ---------------------------------------------------------
    'Mgr.Status.Ready'          = '就绪'
    'Mgr.Status.Summary'        = '用户 PATH：{0} 项    |    系统 PATH：{1} 项    |    备份：{2} 个    |    当前为管理员：{3}    |    备份目录：{4}'

    # ---- 消息中的范围措辞 -----------------------------------------------
    'Mgr.Scope.UserPath'        = '用户 PATH'
    'Mgr.Scope.SystemPath'      = '系统 PATH'

    # ---- 备份内容 -------------------------------------------------------
    'Mgr.Backup.EmptyContent'   = '（该备份内容为空，说明当时 PATH 为空值。）'

    # ---- 消息 -----------------------------------------------------------
    'Mgr.Msg.MissingLibrary'    = '缺少公共函数库：{0}。请确认 lib\Common.ps1 与 PathManager.ps1 位于同一目录。'
    'Mgr.Msg.StartupFailed'     = 'PATH 管理器启动或运行失败：{0}'
    'Mgr.Msg.ErrorLocation'     = '位置：{0}'
    'Mgr.Msg.InitFailed'        = '初始化失败：{0}'
    'Mgr.Msg.RefreshFailed'     = '刷新失败：{0}'
    'Mgr.Msg.OpenDirFailed'     = '无法打开目录：{0}'
    'Mgr.Msg.OpenLogFailed'     = '无法打开日志文件：{0}'
    'Mgr.Msg.NoLogFile'         = '暂无变更日志文件，执行过 PATH 修改后会自动生成。'
    'Mgr.Msg.SelectBackupFirst' = '请先在列表中选中一条备份记录。'
    'Mgr.Msg.ReadBackupFailed'  = '读取备份失败：{0}'
    'Mgr.Msg.ConfirmRestore'    = "确定要把【{0}】恢复到备份 {1} 吗？`r`n`r`n恢复前会先自动备份当前的 {0}，然后用备份内容覆盖。`r`n时间：{2}`r`n大小：{3} 字节"
    'Mgr.Msg.RestoreElevationRequested' = "已请求管理员权限以恢复【{0}】。`r`n`r`n备份文件：{1}`r`n`r`n请在 UAC 提示中点击「是」，随后会弹出恢复结果。完成后点击「刷新」查看最新状态。"
    'Mgr.Msg.RestoreElevationFailed' = "恢复【{0}】需要管理员权限，但提权失败或已被取消。`r`n`r`n备份文件：{1}`r`n{0} 未被修改。"
    'Mgr.Msg.RestoreSucceeded'  = "已恢复【{0}】。`r`n`r`n恢复自：{1}`r`n恢复前的 PATH 已备份为：{2}"
    'Mgr.Msg.RestoreFailed'     = "恢复失败，PATH 未被修改。`r`n`r`n错误信息：{0}"

    # ---- 语言选择器 -----------------------------------------------------
    'Mgr.ToolTip.LanguageSelector' = '切换界面语言，该选择会被保存，下次启动时生效。'
    'Mgr.Msg.LanguageSwitchFailed' = '切换语言失败：{0}'
}
