# -----------------------------------------------------------------------------
# PathAdder 语言包 - 简体中文 - 分片：verify
#
# 归属模块: verify-registration.ps1
# 键名约定: Verify.*
# 占位符使用 .NET 复合格式：{0} {1} ...
#
# 注意：键集合与顺序必须与 lang\en-US\verify.ps1 完全一致。
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- 结果标记（由 Verify.Line.Status 渲染） ----------------------------
    'Verify.Result.Pass'    = '通过'
    'Verify.Result.Fail'    = '失败'
    'Verify.Result.Warn'    = '警告'
    'Verify.Line.Status'    = '  [{0}] {1}'

    # ---- 标题头 -----------------------------------------------------------
    'Verify.Header.Banner'  = '============================================================'
    'Verify.Header.Title'   = ' {0} 右键菜单注册验证'

    # ---- 章节标题 ---------------------------------------------------------
    'Verify.Section.Format'        = '=== {0} ==='
    'Verify.Section.Layer1'        = '第 1 层：注册表结构检查'
    'Verify.Section.Layer12'       = '第 1.2 层：历史注册位置残留检查（老版本升级路径）'
    'Verify.Section.Layer13'       = '第 1.3 层：默认动词安全性（绝不允许被改成我们的菜单项）'
    'Verify.Section.Layer15'       = '第 1.5 层：HKLM 侧 exefile 完好性检查（安装流程绝不允许改动这里）'
    'Verify.Section.Layer3'        = '第 3 层：其他程序的右键菜单（安装/卸载不得误伤）'
    'Verify.Section.Layer2'        = '第 2 层：真实右键菜单枚举（IContextMenu / GetCommandString）'
    'Verify.Section.Layer2Fallback'= '第 2 层降级：按 Explorer 关联解析规则推演（合并视图 HKCR）'
    'Verify.Section.Summary'       = '验证结果汇总'

    # ---- 顶层消息 ---------------------------------------------------------
    'Verify.Msg.RelaunchSta'         = '[验证] 当前线程非 STA，正在以 -STA 重新启动自身……'
    'Verify.Msg.MissingShellMenuLib' = '缺少菜单注册库：{0}'

    # ---- 第 1 层：注册表结构 ----------------------------------------------
    'Verify.Check.Location'                      = '  位置 [{0}] {1}'
    'Verify.Check.SubKey'                        = '    HKCU\{0}'
    'Verify.Check.KeyMissing'                    = '注册表键不存在：HKCU\{0}'
    'Verify.Check.ParentMissingMuiverb'          = '父项缺少 MUIVerb'
    'Verify.Check.ParentMuiverb'                 = '父项 MUIVerb = 「{0}」'
    'Verify.Check.ParentMissingIcon'             = '父项缺少 Icon'
    'Verify.Check.ParentIcon'                    = '父项 Icon = {0}'
    'Verify.Check.ParentMissingNoWorkingDirectory'= '父项缺少 NoWorkingDirectory'
    'Verify.Check.ParentNoWorkingDirectorySet'   = '父项 NoWorkingDirectory 已设置'
    'Verify.Check.ParentLegacySubCommands'       = '父项仍残留上一版的 SubCommands 值：{0}（新方案不需要它，且它会让 Windows 忽略父项 command）'
    'Verify.Check.ParentNoLegacySubCommands'     = '父项未残留旧版 SubCommands 值'
    'Verify.Check.ParentMissingCommand'          = '父项缺少 command 子键！新方案依赖「点击父项弹出菜单」，缺少 command 会表现为「点了没反应」'
    'Verify.Check.CommandEmpty'                  = 'command\(Default) 为空'
    'Verify.Check.CommandMissingNoProfile'       = 'command 缺少 -NoProfile'
    'Verify.Check.CommandMissingExecPolicy'      = 'command 缺少 -ExecutionPolicy Bypass'
    'Verify.Check.CommandFileNotQuoted'          = 'command 的 -File 参数未用双引号包裹脚本路径（中文/空格路径会解析失败）'
    'Verify.Check.CommandNotPicker'              = 'command 未指向本目录的 MenuPicker.ps1：{0}'
    'Verify.Check.CommandMissingTarget'          = 'command 缺少 -Target "%V"（右键时拿不到目标文件路径）'
    'Verify.Check.ParentCommandOk'               = '父项 command 正确指向 MenuPicker.ps1，且已传入 -Target "%V"'
    'Verify.Check.ParentCommandProblem'          = '父项 command：{0}'
    'Verify.Check.PickerExists'                  = 'MenuPicker.ps1 存在'
    'Verify.Check.PickerMissing'                 = '找不到菜单脚本 MenuPicker.ps1：{0}'
    'Verify.Check.ParentLegacyShellTree'         = '父项残留旧版 shell 子命令树（…\PathAdder\shell\…），安装程序应已将其清理'
    'Verify.Check.ParentNoLegacyShellTree'       = '父项未残留旧版 shell 子命令树'
    'Verify.Check.LegacyKeyAbsent'               = '历史位置无残留（键不存在）：HKCU\{0}'
    'Verify.Check.LegacyNoLeftover'              = '历史位置无残留：HKCU\{0}'
    'Verify.Check.LegacyLeftover'                = '历史位置仍有本工具残留（请运行 uninstall.ps1）：HKCU\{0} → {1}'
    'Verify.Check.CannotRead'                    = '无法读取：{0}'
    'Verify.Check.NoDefaultVerb'                 = '{0} 未设置默认动词（安全）'
    'Verify.Check.DefaultVerbHijacked'           = '{0} 的默认动词被改成了「{1}」！这会让双击文件不再是打开，而是弹窗改 PATH —— 必须立即修正'
    'Verify.Check.DefaultVerbSafe'               = '{0} 默认动词 = 「{1}」（非本工具，安全）'
    'Verify.Check.HklmUnreadable'                = '无法读取 HKLM\{0}（可能需要管理员权限才能读取，不影响本工具功能）'
    'Verify.Check.SystemVerbIntact'              = '系统菜单项完好：{0}'
    'Verify.Check.SystemVerbMissing'             = '系统菜单项丢失：{0}（安装流程绝不应影响 HKLM）'
    'Verify.Check.OurVerbInHklm'                 = '我们的菜单项 {0} 出现在 HKLM 中，违反「只写 HKCU」的约束'

    # ---- 第 3 层：第三方菜单 ----------------------------------------------
    'Verify.Check.ThirdPartyPreserved'   = 'HKCR\*\shell 下有 {0} 个第三方菜单项，全部保留：'
    'Verify.Check.NoThirdParty'          = 'HKCR\*\shell 下未枚举到第三方菜单项（可能本机确实没有，或无读取权限）'
    'Verify.Check.LegacyFlatVerb'        = '在 HKCR\*\shell 下出现了本工具的历史扁平菜单项 {0}，注册位置异常'
    'Verify.Check.ExeSystemVerbIntact'   = 'HKCR\exefile\shell 系统菜单项完好：{0}'
    'Verify.Check.ExeSystemVerbMissing'  = 'HKCR\exefile\shell 系统菜单项丢失：{0}'
    'Verify.Check.ExeLegacyLeftover'     = 'HKCR\exefile\shell 仍有历史残留：{0}（请运行 uninstall.ps1）'
    'Verify.Check.MergedParentVisible'   = '本工具父项在合并视图可见：{0}'
    'Verify.Check.MergedParentInvisible' = '合并视图中看不到本工具父项：{0}'

    # ---- 第 2 层：真实菜单枚举 --------------------------------------------
    'Verify.Check.SkipContextMenu'      = '已通过 -SkipContextMenu 跳过本层'
    'Verify.Check.ProbeTxtFailed'       = '无法创建 .txt 探测文件，跳过该目标：{0}'
    'Verify.Check.NoProbeTarget'        = '找不到可用于测试的文件：{0}'
    'Verify.Check.ProbeTargets'         = '  被右键对象（{0} 个）：{1}'
    'Verify.Check.InteropCompileFailed' = '无法编译 COM 互操作程序集（通常表示环境受限/缺少 C# 编译器）：{0}'
    'Verify.Check.ProbeHeader'          = '  ---- 探测：{0} ----'
    'Verify.Check.EnumeratedCount'      = '  Explorer 实际枚举到的菜单项共 {0} 个：'
    'Verify.Check.ParentBuilt'          = '父菜单项已被 Explorer 构建：「{0}」'
    'Verify.Check.ParentNotBuilt'       = '父菜单项未被 Explorer 构建：「{0}」（注册位置可能不被枚举，或尚未重启资源管理器）'
    'Verify.Check.SubmenuDynamic'       = '子菜单由 MenuPicker.ps1 在点击父项后动态弹出，不在 Explorer 静态菜单树内；本层只校验其可用性。'
    'Verify.Check.PickerUsable'         = 'MenuPicker.ps1 可用：{0}'
    'Verify.Check.ParentAndPickerOk'    = '父菜单项已生效且 MenuPicker.ps1 可用——点击父项即可展开 {0} 个动作。'
    'Verify.Check.MenuIncomplete'       = '右键菜单不完整：父项或 MenuPicker.ps1 有问题，详见上方条目。'
    'Verify.Check.EnumFailed'           = '无法完成 IContextMenu 枚举（不影响第 1 层结论）：{0}'
    'Verify.Warn.EnumFailed'            = 'IContextMenu 枚举失败：{0}'

    # ---- 第 2 层降级 ------------------------------------------------------
    'Verify.Check.MergedUnreadable'           = '无法读取合并视图：{0}'
    'Verify.Check.MergedVerbs'                = '  合并视图 HKCR\*\shell 下的 verb：'
    'Verify.Check.MergedParentCommand'        = '父项 command 在合并视图可见：{0}'
    'Verify.Check.MergedParentCommandMissing' = '父项缺少 command 子键：{0}（点击会没反应）'
    'Verify.Check.MergedLegacyShell'          = '父项仍存在旧版 shell 子命令树：{0}'
    'Verify.Check.MergedSystemVerbIntact'     = '系统 verb 仍在合并视图中：{0}'

    # ---- 汇总使用的状态词 -------------------------------------------------
    'Verify.Status.Done'        = '已完成'
    'Verify.Status.NotDone'     = '未完成'
    'Verify.Status.Appeared'    = '已出现'
    'Verify.Status.NotAppeared' = '未出现'
    'Verify.Status.Available'   = 'MenuPicker.ps1 可用'
    'Verify.Status.Unavailable' = '不可用'

    # ---- 汇总 -------------------------------------------------------------
    'Verify.Summary.Structure'       = '  注册结构：单一父菜单项（{0}）+ {1} 个动作（由 MenuPicker.ps1 点击后弹出）'
    'Verify.Summary.Failures'        = '  失败项：{0}'
    'Verify.Summary.Warnings'        = '  提示项：{0}'
    'Verify.Summary.ContextMenu'     = '  真实菜单枚举：{0}'
    'Verify.Summary.AssocResolution' = '  关联解析推演：{0}'
    'Verify.Summary.ParentBuilt'     = '  父菜单项构建：{0}'
    'Verify.Summary.PickerScript'    = '  弹出菜单脚本：{0}'

    # ---- 结论 -------------------------------------------------------------
    'Verify.Conclusion.Failed'       = '  结论：验证未通过。'
    'Verify.Conclusion.AllPass1'     = '  结论：全部通过。父菜单项已被资源管理器实际枚举，'
    'Verify.Conclusion.AllPass2'     = '        MenuPicker.ps1 可用，点击「{0}」即可展开 {1} 个动作。'
    'Verify.Conclusion.RegOk1'       = '  结论：注册表结构完整，父菜单项在 Explorer 的主干查找路径上可见。'
    'Verify.Conclusion.RegOk2'       = '  但本环境的 Shell COM 无法枚举菜单（SHCreateItemFromParsingName 返回'
    'Verify.Conclusion.RegOk3'       = '  E_NOINTERFACE，常见于容器 / 精简系统 / 远程会话），因此未取得菜单'
    'Verify.Conclusion.RegOk4'       = '  实际构建的证据。请在普通桌面会话中右键确认，或重启资源管理器后再看菜单。'
    'Verify.Conclusion.NoEvidence1'  = '  结论：注册表结构检查通过，但未能完成菜单生效性的任何验证。'
    'Verify.Conclusion.NoEvidence2'  = '  因此无法断言右键菜单实际可用——请勿把本结果当作「菜单已生效」的证据。'
    'Verify.Conclusion.NoEvidence3'  = '  请在普通交互式桌面会话中重试：'
    'Verify.Conclusion.NoEvidence4'  = '    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"'

    # ---- 修复建议（验证未通过时输出） -------------------------------------
    'Verify.Advice.RestartExplorer' = '  · 若是「父菜单项未被构建 / 未被枚举」，多半是还没重启资源管理器；'
    'Verify.Advice.CheckEngine'     = '  · 若是「当前用户 PATH」相关报错，检查 PathAdder.ps1 是否完好；'
    'Verify.Advice.Reinstall'       = '  · 若第 1 层结构检查也失败，请先重新运行 install.ps1。'

    # ---- 提示（成功时输出） -----------------------------------------------
    'Verify.Tip.Layered1' = '  提示：Windows 11 的右键菜单已分层，本工具的菜单项位于经典菜单内。'
    'Verify.Tip.Layered2' = '  查看方式：右键 →「显示更多选项」，或选中文件后按 Shift+F10。'
    'Verify.Tip.Restart1' = '  若经典菜单里仍未出现，请重启资源管理器：'
    'Verify.Tip.Restart2' = '    Stop-Process -Name explorer -Force; Start-Process explorer.exe'
}
