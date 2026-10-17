# -----------------------------------------------------------------------------
# PathAdder language pack - English (United States) - shard: gui
#
# Owner module: PathManager.ps1 (WinForms GUI)
# Key convention: Mgr.*
# Placeholders use .NET composite format: {0} {1} ...
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- Window titles ---------------------------------------------------
    'Mgr.Title'                 = 'PATH Manager'
    'Mgr.Title.StartupFailed'   = 'PATH Assistant - Startup failed'
    'Mgr.Title.BackupPreview'   = 'Backup preview - {0}'

    # ---- Path list groups -------------------------------------------------
    'Mgr.Group.UserPath'        = 'User PATH (HKCU\Environment)'
    'Mgr.Group.SystemPath'      = 'System PATH (HKLM\...\Session Manager\Environment)'

    # ---- Generic UI text --------------------------------------------------
    'Mgr.Text.EntryCount'       = '  ({0} entries)'
    'Mgr.Text.EmptyPath'        = '(This PATH is empty)'
    'Mgr.Text.ReadFailed'       = '(Read failed: {0})'

    # ---- Tabs -------------------------------------------------------------
    'Mgr.Tab.Backups'           = 'Backup history'
    'Mgr.Tab.Log'               = 'Change log'

    # ---- Backup list columns ----------------------------------------------
    'Mgr.Column.File'           = 'Backup file'
    'Mgr.Column.Scope'          = 'Scope'
    'Mgr.Column.Time'           = 'Time'
    'Mgr.Column.Size'           = 'Size (bytes)'
    'Mgr.Column.Path'           = 'Full path'

    # ---- Buttons ----------------------------------------------------------
    'Mgr.Button.OpenBackupDir'  = 'Open Backup Folder'
    'Mgr.Button.OpenLog'        = 'Open Change Log'
    'Mgr.Button.Preview'        = 'Preview Contents'
    'Mgr.Button.RestoreToBackup' = 'Restore to This Backup'
    'Mgr.Button.RefreshBackups' = 'Refresh Backup List'

    # ---- Hints / headers --------------------------------------------------
    'Mgr.Hint'                  = 'Tip: changing the System PATH requires administrator rights. Every change is backed up automatically and can be restored from the "Backup history" tab at any time.'
    'Mgr.Log.Header'            = 'Last {0} entries (newest first)   Log format: [time] action=... scope=... dir=... backup=... type=...'
    'Mgr.Log.Empty'             = '(No change log yet. Entries appear here after an add, remove or restore operation.)'

    # ---- Status bar -------------------------------------------------------
    'Mgr.Status.Ready'          = 'Ready'
    'Mgr.Status.Summary'        = 'User PATH: {0} entries    |    System PATH: {1} entries    |    Backups: {2}    |    Running as administrator: {3}    |    Backup folder: {4}'

    # ---- Scope wording used inside messages -------------------------------
    'Mgr.Scope.UserPath'        = 'User PATH'
    'Mgr.Scope.SystemPath'      = 'System PATH'

    # ---- Backup content ---------------------------------------------------
    'Mgr.Backup.EmptyContent'   = '(This backup is empty, which means PATH had no value at the time.)'

    # ---- Messages ---------------------------------------------------------
    'Mgr.Msg.MissingLibrary'    = 'Shared function library is missing: {0}. Make sure lib\Common.ps1 and PathManager.ps1 are located in the same directory.'
    'Mgr.Msg.StartupFailed'     = 'Failed to start or run the PATH Manager: {0}'
    'Mgr.Msg.ErrorLocation'     = 'Location: {0}'
    'Mgr.Msg.InitFailed'        = 'Initialization failed: {0}'
    'Mgr.Msg.RefreshFailed'     = 'Refresh failed: {0}'
    'Mgr.Msg.OpenDirFailed'     = 'Unable to open the folder: {0}'
    'Mgr.Msg.OpenLogFailed'     = 'Unable to open the log file: {0}'
    'Mgr.Msg.NoLogFile'         = 'There is no change log file yet. It is created automatically after the first PATH change.'
    'Mgr.Msg.SelectBackupFirst' = 'Please select a backup entry in the list first.'
    'Mgr.Msg.ReadBackupFailed'  = 'Failed to read the backup: {0}'
    'Mgr.Msg.ConfirmRestore'    = "Restore {0} to backup {1}?`r`n`r`nThe current {0} is backed up first, then overwritten with the backup contents.`r`nTime: {2}`r`nSize: {3} bytes"
    'Mgr.Msg.RestoreElevationRequested' = "Administrator rights have been requested to restore {0}.`r`n`r`nBackup file: {1}`r`n`r`nPlease click ""Yes"" in the UAC prompt; the restore result is shown afterwards. Click Refresh to see the latest state."
    'Mgr.Msg.RestoreElevationFailed' = "Restoring {0} requires administrator rights, but elevation failed or was cancelled.`r`n`r`nBackup file: {1}`r`n{0} was not modified."
    'Mgr.Msg.RestoreSucceeded'  = "Restored {0}.`r`n`r`nRestored from: {1}`r`nThe PATH before the restore was backed up as: {2}"
    'Mgr.Msg.RestoreFailed'     = "Restore failed; PATH was not modified.`r`n`r`nError: {0}"

    # ---- Language selector ------------------------------------------------
    'Mgr.ToolTip.LanguageSelector' = 'Switch the interface language. The choice is saved for the next launch.'
    'Mgr.Msg.LanguageSwitchFailed' = 'Failed to switch the language: {0}'
}
