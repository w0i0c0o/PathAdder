# -----------------------------------------------------------------------------
# PathAdder language pack - English (United States) - shard: verify
#
# Owner module: verify-registration.ps1
# Key convention: Verify.*
# Placeholders use .NET composite format: {0} {1} ...
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- Result markers (rendered through Verify.Line.Status) -------------
    'Verify.Result.Pass'    = 'PASS'
    'Verify.Result.Fail'    = 'FAIL'
    'Verify.Result.Warn'    = 'WARN'
    'Verify.Line.Status'    = '  [{0}] {1}'

    # ---- Header -----------------------------------------------------------
    'Verify.Header.Banner'  = '============================================================'
    'Verify.Header.Title'   = ' {0} context menu registration verification'

    # ---- Section titles ---------------------------------------------------
    'Verify.Section.Format'        = '=== {0} ==='
    'Verify.Section.Layer1'        = 'Layer 1: registry structure check'
    'Verify.Section.Layer12'       = 'Layer 1.2: leftovers at historical registration locations (upgrade path from older versions)'
    'Verify.Section.Layer13'       = 'Layer 1.3: default verb safety (must never become one of our menu entries)'
    'Verify.Section.Layer15'       = 'Layer 1.5: HKLM exefile integrity check (setup must never touch it)'
    'Verify.Section.Layer3'        = 'Layer 3: context menu entries of other programs (setup/uninstall must not break them)'
    'Verify.Section.Layer2'        = 'Layer 2: real context menu enumeration (IContextMenu / GetCommandString)'
    'Verify.Section.Layer2Fallback'= 'Layer 2 fallback: derivation from Explorer association resolution rules (merged view HKCR)'
    'Verify.Section.Summary'       = 'Verification result summary'

    # ---- Top-level messages ------------------------------------------------
    'Verify.Msg.RelaunchSta'         = '[VERIFY] Current thread is not STA; relaunching itself with -STA...'
    'Verify.Msg.MissingShellMenuLib' = 'Menu registration library is missing: {0}'

    # ---- Layer 1: registry structure --------------------------------------
    'Verify.Check.Location'                      = '  Location [{0}] {1}'
    'Verify.Check.SubKey'                        = '    HKCU\{0}'
    'Verify.Check.KeyMissing'                    = 'Registry key does not exist: HKCU\{0}'
    'Verify.Check.ParentMissingMuiverb'          = 'Parent entry is missing MUIVerb'
    'Verify.Check.ParentMuiverb'                 = 'Parent MUIVerb = "{0}"'
    'Verify.Check.ParentMissingIcon'             = 'Parent entry is missing Icon'
    'Verify.Check.ParentIcon'                    = 'Parent Icon = {0}'
    'Verify.Check.ParentMissingNoWorkingDirectory'= 'Parent entry is missing NoWorkingDirectory'
    'Verify.Check.ParentNoWorkingDirectorySet'   = 'Parent NoWorkingDirectory is set'
    'Verify.Check.ParentLegacySubCommands'       = 'Parent entry still carries the previous version SubCommands value: {0} (the new design does not need it, and it makes Windows ignore the parent command)'
    'Verify.Check.ParentNoLegacySubCommands'     = 'Parent entry has no leftover SubCommands value from the previous version'
    'Verify.Check.ParentMissingCommand'          = 'Parent entry is missing the command subkey! The new design relies on "clicking the parent pops up the menu"; without command it behaves as "clicking does nothing"'
    'Verify.Check.CommandEmpty'                  = 'command\(Default) is empty'
    'Verify.Check.CommandMissingNoProfile'       = 'command is missing -NoProfile'
    'Verify.Check.CommandMissingExecPolicy'      = 'command is missing -ExecutionPolicy Bypass'
    'Verify.Check.CommandFileNotQuoted'          = 'the -File argument of command does not wrap the script path in double quotes (paths containing spaces or non-ASCII characters fail to parse)'
    'Verify.Check.CommandNotPicker'              = 'command does not point to MenuPicker.ps1 in this directory: {0}'
    'Verify.Check.CommandMissingTarget'          = 'command is missing -Target "%V" (the target file path cannot be obtained on right-click)'
    'Verify.Check.ParentCommandOk'               = 'Parent command correctly points to MenuPicker.ps1 and passes -Target "%V"'
    'Verify.Check.ParentCommandProblem'          = 'Parent command: {0}'
    'Verify.Check.PickerExists'                  = 'MenuPicker.ps1 exists'
    'Verify.Check.PickerMissing'                 = 'Cannot find the menu script MenuPicker.ps1: {0}'
    'Verify.Check.ParentLegacyShellTree'         = 'Parent entry still has the legacy shell subcommand tree (...\PathAdder\shell\...); setup should have cleaned it up'
    'Verify.Check.ParentNoLegacyShellTree'       = 'Parent entry has no legacy shell subcommand tree'
    'Verify.Check.LegacyKeyAbsent'               = 'No leftover at the historical location (key does not exist): HKCU\{0}'
    'Verify.Check.LegacyNoLeftover'              = 'No leftover at the historical location: HKCU\{0}'
    'Verify.Check.LegacyLeftover'                = 'This tool still has leftovers at the historical location (run uninstall.ps1): HKCU\{0} -> {1}'
    'Verify.Check.CannotRead'                    = 'Cannot read: {0}'
    'Verify.Check.NoDefaultVerb'                 = '{0} has no default verb set (safe)'
    'Verify.Check.DefaultVerbHijacked'           = 'The default verb of {0} was changed to "{1}"! Double-clicking a file would no longer open it but pop up the PATH dialog - this must be fixed immediately'
    'Verify.Check.DefaultVerbSafe'               = 'Default verb of {0} = "{1}" (not ours, safe)'
    'Verify.Check.HklmUnreadable'                = 'Cannot read HKLM\{0} (reading it may require administrator rights; it does not affect this tool)'
    'Verify.Check.SystemVerbIntact'              = 'System menu entry intact: {0}'
    'Verify.Check.SystemVerbMissing'             = 'System menu entry missing: {0} (setup must never affect HKLM)'
    'Verify.Check.OurVerbInHklm'                 = 'Our menu entry {0} appears under HKLM, which violates the "HKCU only" rule'

    # ---- Layer 3: third-party menus ---------------------------------------
    'Verify.Check.ThirdPartyPreserved'   = 'HKCR\*\shell has {0} third-party menu entries, all preserved:'
    'Verify.Check.NoThirdParty'          = 'No third-party menu entry was enumerated under HKCR\*\shell (there may be none on this machine, or read access is denied)'
    'Verify.Check.LegacyFlatVerb'        = 'A legacy flat menu entry of this tool appeared under HKCR\*\shell: {0} - the registration location is wrong'
    'Verify.Check.ExeSystemVerbIntact'   = 'HKCR\exefile\shell system menu entry intact: {0}'
    'Verify.Check.ExeSystemVerbMissing'  = 'HKCR\exefile\shell system menu entry missing: {0}'
    'Verify.Check.ExeLegacyLeftover'     = 'HKCR\exefile\shell still has a legacy leftover: {0} (run uninstall.ps1)'
    'Verify.Check.MergedParentVisible'   = 'Our parent entry is visible in the merged view: {0}'
    'Verify.Check.MergedParentInvisible' = 'Our parent entry is not visible in the merged view: {0}'

    # ---- Layer 2: real menu enumeration ------------------------------------
    'Verify.Check.SkipContextMenu'      = 'This layer was skipped through -SkipContextMenu'
    'Verify.Check.ProbeTxtFailed'       = 'Cannot create the .txt probe file, skipping that target: {0}'
    'Verify.Check.NoProbeTarget'        = 'No file available for testing: {0}'
    'Verify.Check.ProbeTargets'         = '  Right-click targets ({0}): {1}'
    'Verify.Check.InteropCompileFailed' = 'Cannot compile the COM interop assembly (usually a restricted environment or a missing C# compiler): {0}'
    'Verify.Check.ProbeHeader'          = '  ---- Probe: {0} ----'
    'Verify.Check.EnumeratedCount'      = '  Explorer actually enumerated {0} menu entries:'
    'Verify.Check.ParentBuilt'          = 'The parent menu entry was built by Explorer: "{0}"'
    'Verify.Check.ParentNotBuilt'       = 'The parent menu entry was not built by Explorer: "{0}" (the registration location may not be enumerated, or Explorer has not been restarted yet)'
    'Verify.Check.SubmenuDynamic'       = 'The submenu is popped up dynamically by MenuPicker.ps1 after the parent entry is clicked; it is not part of Explorer static menu tree, so this layer only verifies that it is usable.'
    'Verify.Check.PickerUsable'         = 'MenuPicker.ps1 is usable: {0}'
    'Verify.Check.ParentAndPickerOk'    = 'The parent menu entry is live and MenuPicker.ps1 is usable - clicking the parent expands the {0} actions.'
    'Verify.Check.MenuIncomplete'       = 'The context menu is incomplete: there is a problem with the parent entry or MenuPicker.ps1, see the items above.'
    'Verify.Check.EnumFailed'           = 'Cannot complete the IContextMenu enumeration (does not affect the layer 1 conclusion): {0}'
    'Verify.Warn.EnumFailed'            = 'IContextMenu enumeration failed: {0}'

    # ---- Layer 2 fallback --------------------------------------------------
    'Verify.Check.MergedUnreadable'           = 'Cannot read the merged view: {0}'
    'Verify.Check.MergedVerbs'                = '  Verbs under the merged view HKCR\*\shell:'
    'Verify.Check.MergedParentCommand'        = 'The parent command is visible in the merged view: {0}'
    'Verify.Check.MergedParentCommandMissing' = 'The parent entry is missing the command subkey: {0} (clicking it does nothing)'
    'Verify.Check.MergedLegacyShell'          = 'The parent entry still has the legacy shell subcommand tree: {0}'
    'Verify.Check.MergedSystemVerbIntact'     = 'System verb still present in the merged view: {0}'

    # ---- Status words used by the summary ----------------------------------
    'Verify.Status.Done'        = 'done'
    'Verify.Status.NotDone'     = 'not done'
    'Verify.Status.Appeared'    = 'yes'
    'Verify.Status.NotAppeared' = 'no'
    'Verify.Status.Available'   = 'MenuPicker.ps1 usable'
    'Verify.Status.Unavailable' = 'unusable'

    # ---- Summary -----------------------------------------------------------
    'Verify.Summary.Structure'       = '  Registration layout: a single parent menu entry ({0}) + {1} actions (popped up by MenuPicker.ps1 after the click)'
    'Verify.Summary.Failures'        = '  Failures: {0}'
    'Verify.Summary.Warnings'        = '  Warnings: {0}'
    'Verify.Summary.ContextMenu'     = '  Real menu enumeration: {0}'
    'Verify.Summary.AssocResolution' = '  Association resolution: {0}'
    'Verify.Summary.ParentBuilt'     = '  Parent menu entry built: {0}'
    'Verify.Summary.PickerScript'    = '  Popup menu script: {0}'

    # ---- Conclusion --------------------------------------------------------
    'Verify.Conclusion.Failed'       = '  Result: verification FAILED.'
    'Verify.Conclusion.AllPass1'     = '  Result: all checks passed. The parent menu entry was actually enumerated by Explorer and'
    'Verify.Conclusion.AllPass2'     = '        MenuPicker.ps1 is usable, so clicking "{0}" expands the {1} actions.'
    'Verify.Conclusion.RegOk1'       = '  Result: the registry structure is complete and the parent menu entry is visible on Explorer main lookup path.'
    'Verify.Conclusion.RegOk2'       = '  However, the Shell COM of this environment cannot enumerate menus (SHCreateItemFromParsingName'
    'Verify.Conclusion.RegOk3'       = '  returns E_NOINTERFACE, common in containers / trimmed systems / remote sessions), so no'
    'Verify.Conclusion.RegOk4'       = '  evidence that the menu is really built was obtained. Please right-click in a normal desktop session to confirm, or restart Explorer and check the menu again.'
    'Verify.Conclusion.NoEvidence1'  = '  Result: the registry structure check passed, but no verification of menu effectiveness could be completed.'
    'Verify.Conclusion.NoEvidence2'  = '  Therefore it cannot be asserted that the context menu really works - do not take this result as evidence that the menu is live.'
    'Verify.Conclusion.NoEvidence3'  = '  Please retry in a normal interactive desktop session:'
    'Verify.Conclusion.NoEvidence4'  = '    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"'

    # ---- Advice (printed when verification failed) -------------------------
    'Verify.Advice.RestartExplorer' = '  - If the parent menu entry "was not built / was not enumerated", Explorer most likely has not been restarted yet;'
    'Verify.Advice.CheckEngine'     = '  - If the errors mention the current user PATH, check whether PathAdder.ps1 is intact;'
    'Verify.Advice.Reinstall'       = '  - If the layer 1 structure check also failed, run install.ps1 again first.'

    # ---- Tips (printed on success) -----------------------------------------
    'Verify.Tip.Layered1' = '  Note: the Windows 11 context menu is layered, and the entries of this tool live in the classic menu.'
    'Verify.Tip.Layered2' = '  How to see it: right-click and choose "Show more options", or select the file and press Shift+F10.'
    'Verify.Tip.Restart1' = '  If it still does not appear in the classic menu, restart Explorer:'
    'Verify.Tip.Restart2' = '    Stop-Process -Name explorer -Force; Start-Process explorer.exe'
}
