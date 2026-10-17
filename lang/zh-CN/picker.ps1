# -----------------------------------------------------------------------------
# PathAdder language pack - 简体中文 - shard: picker
#
# 归属模块: MenuPicker.ps1 (click-popup fallback menu) | Picker.*
# 占位符使用 .NET 复合格式：{0} {1} ...
#
# 注意：本分片只服务于 MenuPicker.ps1 弹出的操作菜单；资源管理器右键菜单由
# 注册表提供，使用的是 shell.ps1 里的 Shell.* 键。
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- 菜单项（与 Shell.Verb.* 一一对应）--------------------------------
    'Picker.Item.AddUser'     = '添加到 PATH（当前用户）'
    'Picker.Item.AddSystem'   = '添加到 PATH（系统全局，管理员）'
    'Picker.Item.Remove'      = '从 PATH 中移除此目录'
    'Picker.Item.OpenManager' = '打开 PATH 管理器'

    # ---- 错误信息 --------------------------------------------------------
    'Picker.Error.FormsLoadFailed' = '无法加载 Windows.Forms 组件，PATH 助手菜单无法启动：{0}'
    'Picker.Error.EngineMissing'   = '找不到 PathAdder.ps1，脚本已移动或损坏。{0}{0}期望位置：{1}'
    'Picker.Error.ShowFailed'      = '菜单显示失败：{0}'
    'Picker.Error.ExecuteFailed'   = '执行失败：{0}'
}
