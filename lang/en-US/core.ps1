# -----------------------------------------------------------------------------
# PathAdder language pack - English (United States) - shard: core
#
# Owner module: lib\Common.ps1 (shared library) + framework-wide shared keys
# Key convention: App.* / Core.*
# Placeholders use .NET composite format: {0} {1} ...
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- Application identity -------------------------------------------
    'App.Name'              = 'PATH Assistant'
    'App.Language.en-US'    = 'English'
    'App.Language.zh-CN'    = 'Simplified Chinese'

    # ---- Generic buttons / labels ---------------------------------------
    'App.Button.OK'         = 'OK'
    'App.Button.Cancel'     = 'Cancel'
    'App.Button.Close'      = 'Close'
    'App.Button.Yes'        = 'Yes'
    'App.Button.No'         = 'No'
    'App.Button.Refresh'    = 'Refresh'
    'App.Button.Browse'     = 'Browse...'
    'App.Button.Apply'      = 'Apply'
    'App.Button.Delete'     = 'Delete'
    'App.Button.Restore'    = 'Restore'
    'App.Button.Backup'     = 'Back up'
    'App.Button.Export'     = 'Export'
    'App.Button.Open'       = 'Open'
    'App.Button.Help'       = 'Help'
    'App.Language'          = 'Language'

    # ---- Scope ----------------------------------------------------------
    'App.Scope.User'        = 'User'
    'App.Scope.System'      = 'System (all users)'
    'App.Scope.All'         = 'User + System'

    # ---- Operation status ------------------------------------------------
    'App.Status.Added'      = 'Added'
    'App.Status.Removed'    = 'Removed'
    'App.Status.AlreadyExists' = 'Already present'
    'App.Status.NotFound'   = 'Not found'
    'App.Status.Failed'     = 'Failed'
    'App.Status.Skipped'    = 'Skipped'

    # ---- Shared messages -------------------------------------------------
    'App.Msg.AdminRequired' = 'Administrator rights are required for this operation.'
    'App.Msg.UacCancelled'  = 'Elevation was cancelled or refused, so nothing was changed.'
    'App.Msg.UnknownError'  = 'Unknown error.'
    'App.Msg.OperationCancelled' = 'Operation cancelled.'

    # ---- Shared library errors / warnings (lib\Common.ps1) ----------------
    'Core.Err.RegistryKeyOpenFailed'    = 'Unable to open the registry key (it does not exist, or read access was denied).'
    'Core.Err.RegistryWriteOpenFailed'  = 'Failed to open the registry for writing (are administrator rights required?): {0}'
    'Core.Err.RegistryWriteHandleFailed' = 'Failed to open the registry for writing: no writable handle for the {0} Environment key.'
    'Core.Err.BackupFileNotFound'       = 'The backup file does not exist: {0}'
    'Core.Warn.UnknownPathValueKind'    = 'The PATH value type is unknown or is not a string type ({0}); this tool only handles string values. It has been reset to ExpandString - please verify the PATH contents manually before continuing.'

    # ---- Add / Remove results (lib\Common.ps1) ----------------------------
    'Core.Msg.Add.DirEmpty'      = 'The directory is empty, so nothing was added.'
    'Core.Msg.Add.InvalidDir'    = 'The directory path is invalid (it must be a usable absolute path): {0}'
    'Core.Msg.Remove.DirEmpty'   = 'The directory is empty, so nothing was removed.'
    'Core.Msg.Remove.InvalidDir' = 'The directory path is invalid (it must be an absolute path): {0}'
    'Core.Msg.DirNotFound'       = 'The directory does not exist: {0}'
    'Core.Msg.ReadPathFailed'    = 'Failed to read PATH: {0}'
    'Core.Msg.WritePathFailed'   = 'Failed to write PATH (a backup was kept: {0}): {1}'
    'Core.Msg.Add.AlreadyExists' = 'The directory is already in PATH, so nothing was changed.'
    'Core.Msg.Remove.NotFound'   = 'The directory is not in PATH, so nothing was changed.'
    'Core.Msg.Added'             = 'Added to PATH.'
    'Core.Msg.Removed'           = 'Removed from PATH.'

    # ---- Change log field labels (lib\Common.ps1) -------------------------
    'Core.Log.Label.Action'      = 'action='
    'Core.Log.Label.Scope'       = 'scope='
    'Core.Log.Label.Directory'   = 'dir='
    'Core.Log.Label.Backup'      = 'backup='
    'Core.Log.Label.Kind'        = 'kind='
    'Core.Log.RestoreFrom'       = 'restored from {0}'
}
