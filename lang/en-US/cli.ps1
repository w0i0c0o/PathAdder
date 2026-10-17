# -----------------------------------------------------------------------------
# PathAdder language pack - English (United States) - shard: cli
#
# Owner module: PathAdder.ps1 (command line engine)
# Key convention: Cli.*
# Placeholders use .NET composite format: {0} {1} ...
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- Startup errors -----------------------------------------------------
    'Cli.Error.MissingLibrary'  = 'The shared function library is missing: {0}'

    # ---- Shared labels ------------------------------------------------------
    'Cli.Label.BackupFile'      = 'Backup file: {0}'
    'Cli.Label.Directory'       = 'Directory: {0}'
    'Cli.Label.ErrorDetail'     = 'Error details: {0}'
    'Cli.Label.RestoredFrom'    = 'Restored from backup: {0}'
    'Cli.Label.RestoredBackup'  = 'The PATH before this restore was backed up as: {0}'

    # ---- Per-scope result sentences -----------------------------------------
    'Cli.Result.NotExecuted'    = '[{0}]: nothing was executed.'
    'Cli.Result.Added'          = 'Successfully added to [{0}].'
    'Cli.Result.AlreadyExists'  = 'The directory is already present in [{0}]; nothing was changed.'
    'Cli.Result.Removed'        = 'Successfully removed from [{0}].'
    'Cli.Result.NotFound'       = 'The directory is not present in [{0}]; nothing was changed.'
    'Cli.Result.Failed'         = 'The operation failed for [{0}]: {1}'
    'Cli.Result.Unknown'        = 'Unknown status for [{0}]: {1}'
    'Cli.Result.Success'        = 'The operation succeeded.'
    'Cli.Result.NoChange'       = 'No change was needed.'
    'Cli.Result.Incomplete'     = 'The operation did not complete.'

    # ---- PATH manager -------------------------------------------------------
    'Cli.Manager.NotFound'      = 'The PATH manager script was not found.'
    'Cli.Manager.StartFailed'   = 'Failed to start the PATH manager.'

    # ---- Restore ------------------------------------------------------------
    'Cli.Restore.MissingBackupFile'    = 'The -BackupFile parameter is required when restoring a backup. The operation was cancelled.'
    'Cli.Restore.StillNotAdmin'        = 'Administrator rights are still unavailable, so the system PATH cannot be restored.'
    'Cli.Restore.ElevationRequested'   = 'Administrator rights were requested in order to restore the system PATH.'
    'Cli.Restore.UacHint'              = 'Click "Yes" in the UAC prompt; the restore result is shown afterwards.'
    'Cli.Restore.ElevationFailed'      = 'Restoring the system PATH requires administrator rights, but the elevation failed or was cancelled.'
    'Cli.Restore.Failed'               = 'The restore failed. PATH was not modified.'
    'Cli.Restore.Succeeded'            = '[{0}] has been restored.'

    # ---- Target resolution --------------------------------------------------
    'Cli.Target.ResolveFailed'  = 'The target file or directory could not be resolved:'
    'Cli.Target.AddReason'      = 'Make sure the file or directory exists and use a full absolute path (for example D:\Tools\bin\myapp.exe).'
    'Cli.Target.RemoveReason'   = 'Removal accepts a target that no longer exists, but a full absolute path is still required (for example D:\Tools\bin).'

    # ---- Single-scope operation ---------------------------------------------
    'Cli.Operation.Failed'      = 'The operation failed. PATH was not modified.'

    # ---- System scope elevation ---------------------------------------------
    'Cli.System.StillNotAdmin'  = 'Administrator rights are still unavailable, so the system PATH cannot be modified.'
    'Cli.System.AdminHint'      = 'Ask an administrator account to run this action, or use "Add to PATH (current user)" instead.'
    'Cli.System.ElevationFailed' = 'Administrator rights are required to {0} the system PATH, but the elevation failed or "No" was chosen in the UAC prompt.'
    'Cli.System.NoAdminHint'    = 'To avoid administrator rights, use "Add to PATH (current user)".'
    'Cli.Verb.Add'              = 'add'
    'Cli.Verb.Remove'           = 'remove'

    # ---- Notes for Scope = All ----------------------------------------------
    'Cli.All.SystemNoAdminNote'           = '(Administrator rights were not granted; the system PATH was not processed.)'
    'Cli.All.SystemElevationRequestedNote' = '(Administrator rights were requested to process the system PATH. Click "Yes" in the UAC prompt; a separate result dialog follows.)'
    'Cli.All.SystemElevationFailedNote'    = '(The system PATH requires administrator rights; the elevation failed or was cancelled, so nothing was changed.)'

    # ---- Shared closing hints -----------------------------------------------
    'Cli.Msg.PathNotModified'        = 'PATH was not modified.'
    'Cli.Msg.SystemPathNotModified'  = 'The system PATH was not modified.'
    'Cli.Msg.NewWindowsHint'         = 'Newly opened command prompt windows use the restored PATH.'
    'Cli.Msg.EffectHint'             = 'The change takes effect in newly opened command prompt (cmd / PowerShell) windows; already open windows must be restarted.'
    'Cli.All.EffectHint'             = 'The change takes effect in newly opened command prompt windows; already open windows must be restarted.'
}
