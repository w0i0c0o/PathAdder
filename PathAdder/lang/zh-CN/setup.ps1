# -----------------------------------------------------------------------------
# PathAdder 语言包 - 简体中文 - 分片：setup
#
# 归属模块: install.ps1 / uninstall.ps1 / *.bat
# 键名约定: Setup.*
# 占位符使用 .NET 复合格式：{0} {1} ...
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- 共用错误 / 标签 -----------------------------------------------------
    'Setup.Error.MissingLibrary'      = '缺少公共函数库：{0}'
    'Setup.Error.MissingShellMenuLib' = '缺少菜单注册库：{0}'
    'Setup.Error.RestartConflict'     = '参数冲突：-RestartExplorer 与 -NoRestart 不能同时使用。'
    'Setup.Error.RestartConflictHint' = '请只指定其中一个，或都不指定（走询问模式）。'
    'Setup.Label.RefreshStatus'       = '刷新状态：{0}'
    'Setup.Label.BackupDirectory'     = '备份目录：{0}'
    'Setup.Label.HkcuKey'             = '  HKCU\{0}'

    # ---- install.ps1：前置检查 -----------------------------------------------
    'Setup.Install.MissingFiles'        = '安装中止：缺少必要文件 {0}'
    'Setup.Install.MissingFilesHint'    = '请确认这些文件与 install.ps1 位于同一目录。'
    'Setup.Install.Failed'              = '安装失败：{0}'
    'Setup.Install.MenuUnchanged'       = '系统右键菜单未被修改。'
    'Setup.Install.RegistryIncomplete'  = '安装失败：注册表写入未完成。'
    'Setup.Install.PartialHint'         = '系统右键菜单可能只被部分修改，请运行 uninstall.ps1 后重试。'
    'Setup.Install.MakeDefaultDeprecated' = '提示：-MakeDefault 已废弃且未生效。本工具**在任何位置都不写入默认动词**——那会改变文件的双击行为（双击不再打开、而是弹窗改 PATH）。'

    # ---- 资源管理器重启 -------------------------------------------------------
    'Setup.Restart.Written'           = 'PATH 助手已写入注册表。'
    'Setup.Restart.Question'          = '是否立即重启资源管理器，使右键菜单生效？'
    'Setup.Restart.Warning'           = '注意：重启资源管理器会关闭所有已打开的文件夹窗口。'
    'Setup.Restart.SuggestNo'         = '（若你正在使用文件夹窗口，建议先选「否」，稍后自行重启。）'
    'Setup.Restart.Succeeded'         = '资源管理器已重启，菜单现在应该可以看到了。'
    'Setup.Restart.Failed'            = '重启资源管理器失败：{0}'
    'Setup.Restart.Declined'          = '尚未重启资源管理器 —— **这一步通常是必需的**。'

    # ---- install.ps1：完成报告 ------------------------------------------------
    'Setup.Install.Completed'         = 'PATH 助手已安装完成（注册表已写入）。'
    'Setup.Install.NextStepTitle'     = '【下一步：必须重启资源管理器，菜单才会出现】'
    'Setup.Install.CurrentStatus'     = '当前状态：{0}'
    'Setup.Install.ChooseOne'         = '请二选一完成重启：'
    'Setup.Install.MethodManual'      = '  1) 手动执行（PowerShell）：'
    'Setup.Install.MethodCommand'     = '     Stop-Process -Name explorer -Force; Start-Process explorer.exe'
    'Setup.Install.MethodLogoff'      = '  2) 注销当前 Windows 账户后重新登录'
    'Setup.Install.ShnNote'           = '  （SHChangeNotify 通知已发出，但 Windows 11 上它经常不足够，'
    'Setup.Install.ShnNote2'          = '    实测必须重启 explorer 或注销重登才会真正生效。）'
    'Setup.Install.WhereTitle'        = '【菜单在哪里】'
    'Setup.Install.WhereBody'         = '在任意文件（任意类型，含 .exe）上右键，菜单里会出现一项「PATH 助手」，把鼠标悬停或点开它，即可看到 4 个子项：'
    'Setup.Install.SubItem.AddUser'   = '  · 添加到 PATH（当前用户）'
    'Setup.Install.SubItem.AddSystem' = '  · 添加到 PATH（系统全局，管理员）'
    'Setup.Install.SubItem.Remove'    = '  · 从 PATH 中移除此目录'
    'Setup.Install.SubItem.Manager'   = '  · 打开 PATH 管理器'
    'Setup.Install.Win11Menu'         = 'Windows 11 的菜单是分层的，请按以下任一方式查看：'
    'Setup.Install.Win11Way1'         = '  · 右键 →「显示更多选项」'
    'Setup.Install.Win11Way2'         = '  · 选中文件后按 Shift+F10'
    'Setup.Install.Win11Way3'         = '  · 选中文件后按 Shift+方向键'
    'Setup.Install.InfoTitle'         = '【安装信息】'
    'Setup.Install.RegLocation'       = '注册位置（用户级，无需管理员）：'
    'Setup.Install.SubCommands'       = '级联子命令：{0}'

    # ---- uninstall.ps1 --------------------------------------------------------
    'Setup.Uninstall.Failed'           = '卸载失败：{0}'
    'Setup.Uninstall.RemovedNotice'    = 'PATH 助手的右键菜单已移除。'
    'Setup.Uninstall.RestartQuestion'  = '是否立即重启资源管理器，让菜单变化生效？'
    'Setup.Uninstall.RestartWarning'   = '注意：重启资源管理器会关闭所有已打开的文件夹窗口。'
    'Setup.Uninstall.NextStepTitle'    = '【下一步：建议重启资源管理器】'
    'Setup.Uninstall.RestartSucceeded' = '资源管理器已重启。'
    'Setup.Uninstall.RestartFailed'    = '重启失败：{0}'
    'Setup.Uninstall.NotRestarted'     = '尚未重启资源管理器。若要立即生效，请执行：'
    'Setup.Uninstall.RestartCommand'   = '  Stop-Process -Name explorer -Force; Start-Process explorer.exe'
    'Setup.Uninstall.RestartAlt'       = '或注销后重新登录。'
    'Setup.Uninstall.CleanedSummary'   = '已清理的位置（共 {0} 处扫描，删除 {1} 项）：'
    'Setup.Uninstall.LocationItem'     = '  · HKCU\{0}'
    'Setup.Uninstall.NothingFound'     = '未发现 PATH 助手的右键菜单项，无需卸载（重复运行不会报错）。'
    'Setup.Uninstall.DeleteFailed'     = '以下项删除失败：{0}'
    'Setup.Uninstall.PrunedEmptyKeys'  = '已回收安装时创建的空键：'
    'Setup.Uninstall.PrunedItem'       = '  {0}'
    'Setup.Uninstall.KeptNote'         = '已保留（未触碰）：系统原有的 open / runas / runasuser 菜单，以及其他程序注册的右键菜单项。'
    'Setup.Uninstall.BackupKept'       = '备份与日志保留在：'
    'Setup.Uninstall.ManualCleanup'    = '如需彻底清理，请手动删除上述目录。'
}
