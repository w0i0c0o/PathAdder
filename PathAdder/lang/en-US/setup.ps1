# -----------------------------------------------------------------------------
# PathAdder language pack - English (United States) - shard: setup
#
# Owner module: install.ps1 / uninstall.ps1 / *.bat
# Key convention: Setup.*
# Placeholders use .NET composite format: {0} {1} ...
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- Shared errors / labels ---------------------------------------------
    'Setup.Error.MissingLibrary'      = 'The shared function library is missing: {0}'
    'Setup.Error.MissingShellMenuLib' = 'The menu registration library is missing: {0}'
    'Setup.Error.RestartConflict'     = 'Parameter conflict: -RestartExplorer and -NoRestart cannot be used together.'
    'Setup.Error.RestartConflictHint' = 'Specify only one of them, or neither (interactive prompt mode).'
    'Setup.Label.RefreshStatus'       = 'Refresh status: {0}'
    'Setup.Label.BackupDirectory'     = 'Backup directory: {0}'
    'Setup.Label.HkcuKey'             = '  HKCU\{0}'

    # ---- install.ps1: preconditions -----------------------------------------
    'Setup.Install.MissingFiles'        = 'Installation aborted: the following required file(s) are missing: {0}'
    'Setup.Install.MissingFilesHint'    = 'Make sure these files are located in the same directory as install.ps1.'
    'Setup.Install.Failed'              = 'Installation failed: {0}'
    'Setup.Install.MenuUnchanged'       = 'The right-click menu was not modified.'
    'Setup.Install.RegistryIncomplete'  = 'Installation failed: the registry was not written completely.'
    'Setup.Install.PartialHint'         = 'The right-click menu may have been modified only partially. Run uninstall.ps1 and try again.'
    'Setup.Install.MakeDefaultDeprecated' = 'Note: -MakeDefault is deprecated and had no effect. This tool never writes a default verb anywhere -- doing so would change the double-click behaviour: files would no longer open, they would show a PATH dialog instead.'

    # ---- Windows Explorer restart -------------------------------------------
    'Setup.Restart.Written'           = 'PATH Assistant has been written to the registry.'
    'Setup.Restart.Question'          = 'Do you want to restart Windows Explorer now so that the right-click menu takes effect?'
    'Setup.Restart.Warning'           = 'Note: restarting Windows Explorer closes all open folder windows.'
    'Setup.Restart.SuggestNo'         = '(If you are using folder windows, choosing "No" and restarting later is recommended.)'
    'Setup.Restart.Succeeded'         = 'Windows Explorer has been restarted; the menu should be visible now.'
    'Setup.Restart.Failed'            = 'Failed to restart Windows Explorer: {0}'
    'Setup.Restart.Declined'          = 'Windows Explorer has not been restarted -- **this step is usually required**.'

    # ---- install.ps1: completion report -------------------------------------
    'Setup.Install.Completed'         = 'PATH Assistant has been installed (registry written).'
    'Setup.Install.NextStepTitle'     = '[Next step: Windows Explorer must be restarted, otherwise the menu does not appear]'
    'Setup.Install.CurrentStatus'     = 'Current status: {0}'
    'Setup.Install.ChooseOne'         = 'Complete the restart with either option:'
    'Setup.Install.MethodManual'      = '  1) Manually (PowerShell):'
    'Setup.Install.MethodCommand'     = '     Stop-Process -Name explorer -Force; Start-Process explorer.exe'
    'Setup.Install.MethodLogoff'      = '  2) Sign out of the current Windows account and sign back in'
    'Setup.Install.ShnNote'           = '  (A SHChangeNotify notification was already sent, but on Windows 11 it is often not enough;'
    'Setup.Install.ShnNote2'          = '    restarting explorer or signing out and back in is what actually makes it take effect.)'
    'Setup.Install.WhereTitle'        = '[Where is the menu]'
    'Setup.Install.WhereBody'         = 'Right-click any file (any type, including .exe): the menu shows a "PATH Assistant" entry. Hover over it or open it to see 4 sub-items:'
    'Setup.Install.SubItem.AddUser'   = '  - Add to PATH (current user)'
    'Setup.Install.SubItem.AddSystem' = '  - Add to PATH (system-wide, administrator)'
    'Setup.Install.SubItem.Remove'    = '  - Remove this directory from PATH'
    'Setup.Install.SubItem.Manager'   = '  - Open PATH Manager'
    'Setup.Install.Win11Menu'         = 'The Windows 11 menu is layered; open it in any of these ways:'
    'Setup.Install.Win11Way1'         = '  - Right-click, then "Show more options"'
    'Setup.Install.Win11Way2'         = '  - Select the file and press Shift+F10'
    'Setup.Install.Win11Way3'         = '  - Select the file and press Shift+Arrow keys'
    'Setup.Install.InfoTitle'         = '[Installation details]'
    'Setup.Install.RegLocation'       = 'Registration location (user level, no administrator rights needed):'
    'Setup.Install.SubCommands'       = 'Cascading sub-commands: {0}'

    # ---- uninstall.ps1 ------------------------------------------------------
    'Setup.Uninstall.Failed'           = 'Uninstallation failed: {0}'
    'Setup.Uninstall.RemovedNotice'    = 'The PATH Assistant right-click menu has been removed.'
    'Setup.Uninstall.RestartQuestion'  = 'Do you want to restart Windows Explorer now so that the menu change takes effect?'
    'Setup.Uninstall.RestartWarning'   = 'Note: restarting Windows Explorer closes all open folder windows.'
    'Setup.Uninstall.NextStepTitle'    = '[Next step: restarting Windows Explorer is recommended]'
    'Setup.Uninstall.RestartSucceeded' = 'Windows Explorer has been restarted.'
    'Setup.Uninstall.RestartFailed'    = 'Restart failed: {0}'
    'Setup.Uninstall.NotRestarted'     = 'Windows Explorer has not been restarted. To apply the change immediately, run:'
    'Setup.Uninstall.RestartCommand'   = '  Stop-Process -Name explorer -Force; Start-Process explorer.exe'
    'Setup.Uninstall.RestartAlt'       = 'Or sign out and sign back in.'
    'Setup.Uninstall.CleanedSummary'   = 'Cleaned locations ({0} locations scanned, {1} entries removed):'
    'Setup.Uninstall.LocationItem'     = '  - HKCU\{0}'
    'Setup.Uninstall.NothingFound'     = 'No PATH Assistant right-click entry was found; there is nothing to uninstall (running this again reports no error).'
    'Setup.Uninstall.DeleteFailed'     = 'The following entries could not be deleted: {0}'
    'Setup.Uninstall.PrunedEmptyKeys'  = 'Empty keys created during installation have been removed:'
    'Setup.Uninstall.PrunedItem'       = '  {0}'
    'Setup.Uninstall.KeptNote'         = 'Left untouched: the built-in open / runas / runasuser menu entries and right-click entries registered by other programs.'
    'Setup.Uninstall.BackupKept'       = 'Backups and logs are kept in:'
    'Setup.Uninstall.ManualCleanup'    = 'To clean up completely, delete the directory above manually.'
}
