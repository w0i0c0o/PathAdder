# -----------------------------------------------------------------------------
# PathAdder language pack - 简体中文 - shard: shell
#
# 归属模块: 右键菜单注册（lib\ShellMenu.ps1）
# 键名约定: Shell.*
# 占位符使用 .NET 复合格式：{0} {1} ...
#
# 重要提示 —— 切换语言后需要重新注册：
#   本分片里的 Shell.Parent.Label 与 Shell.Verb.* 是 Install-PathAdderShellMenu
#   写进注册表的**菜单显示名**。Windows 在注册表里保存的是纯文本字面量，取词发生
#   在注册那一刻、用的是当时生效的语言。因此切换语言**不会**重写已经注册好的菜单
#   项：用户需要重新运行 install.ps1（或重新注册右键菜单），资源管理器里的菜单文字
#   才会刷新。这是注册表 verb 的固有行为，代码层面不做变通。
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- 注册表显示名（最直观的用户可见文案）----------------------------
    'Shell.Parent.Label'     = 'PATH 助手'
    'Shell.Verb.AddUser'     = '添加到 PATH（当前用户）'
    'Shell.Verb.AddSystem'   = '添加到 PATH（系统全局，管理员）'
    'Shell.Verb.Remove'      = '从 PATH 中移除此目录'
    'Shell.Verb.OpenManager' = '打开 PATH 管理器'

    # ---- 位置说明（由 verify-registration.ps1 打印）----------------------
    'Shell.Location.AllFiles'         = '所有文件类型（`*` 覆盖任意扩展名，含 .exe）'
    'Shell.Cleanup.CurrentSubtree'    = '当前版本：所有文件类型的级联菜单（整棵子树均为本工具所有）'
    'Shell.Cleanup.LegacyFlatVerbs'   = '历史遗留：早期版本扁平注册的 4 个 verb'
    'Shell.Cleanup.LegacyExeFallback' = '历史遗留：早期版本的 .exe 兜底注册'

    # ---- 安装错误 --------------------------------------------------------
    'Shell.Error.CreateKeyFailed'         = '无法创建注册表键：HKCU\{0}（{1}）'
    'Shell.Error.CreateKeyFailedNoDetail' = '无法创建注册表键：HKCU\{0}'
    'Shell.Error.PickerMissing'           = '找不到菜单脚本：{0}。请确认 MenuPicker.ps1 与 PathAdder.ps1 位于同一目录。'

    # ---- 卸载报告 --------------------------------------------------------
    'Shell.Uninstall.RemovedSubtree' = '{0}（整棵子树）'

    # ---- Shell 关联缓存刷新 ----------------------------------------------
    'Shell.Refresh.InteropFailed' = '未能加载 shell32 互操作程序集，已跳过资源管理器刷新。请手动重启资源管理器或注销后重新登录。'
    'Shell.Refresh.Notified'      = '已通知资源管理器刷新文件关联（SHCNE_ASSOCCHANGED + SHCNE_UPDATEITEM）。'
    'Shell.Refresh.Failed'        = '通知资源管理器刷新失败（不影响菜单注册结果）：{0}请手动重启资源管理器或注销后重新登录。'

    # ---- 确认框降级（无图形界面）----------------------------------------
    'Shell.Confirm.PrefixedMessage' = '[PATH 助手] {0}'
    'Shell.Confirm.NoGui'           = '[PATH 助手] 当前环境无图形界面，已按「否」处理（不会重启资源管理器）。'
    'Shell.Confirm.BoxFailed'       = '[PATH 助手] 无法显示确认框，已按「否」处理（不会重启资源管理器）。'

    # ---- 重启资源管理器 --------------------------------------------------
    'Shell.Restart.Success' = '资源管理器已重启（原 {0} 个 explorer 进程）。'
    'Shell.Restart.Failed'  = '重启资源管理器失败（菜单注册不受影响）：{0}{1}请手动执行：Stop-Process -Name explorer -Force; Start-Process explorer.exe'
}
