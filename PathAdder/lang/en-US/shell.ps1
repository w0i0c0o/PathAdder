# -----------------------------------------------------------------------------
# PathAdder language pack - English (United States) - shard: shell
#
# Owner module: Shell menu registration (lib\ShellMenu.ps1)
# Key convention: Shell.*
# Placeholders use .NET composite format: {0} {1} ...
#
# IMPORTANT - re-registration after a language switch:
#   The Shell.Parent.Label and Shell.Verb.* values in this shard are the *display
#   names written into the registry* by Install-PathAdderShellMenu. Windows stores
#   them as plain literals, so they are resolved in whatever language is active at
#   registration time. Switching the language later does NOT rewrite entries that
#   are already registered: the user has to re-run install.ps1 (or otherwise
#   re-register the shell menu) for the context menu to show the new language.
#   This is inherent to registry verbs and is not worked around in the code.
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- Registry display names (the most user-visible strings) ----------
    'Shell.Parent.Label'    = 'PATH Assistant'
    'Shell.Verb.AddUser'    = 'Add to PATH (current user)'
    'Shell.Verb.AddSystem'  = 'Add to PATH (system-wide, administrator)'
    'Shell.Verb.Remove'     = 'Remove this folder from PATH'
    'Shell.Verb.OpenManager' = 'Open PATH Manager'

    # ---- Location descriptions (printed by verify-registration.ps1) ------
    'Shell.Location.AllFiles'        = 'All file types (`*` covers every extension, including .exe)'
    'Shell.Cleanup.CurrentSubtree'   = 'Current version: cascading menu for all file types (this tool owns the entire subtree)'
    'Shell.Cleanup.LegacyFlatVerbs'  = 'Legacy: the 4 flat verbs registered by early versions'
    'Shell.Cleanup.LegacyExeFallback' = 'Legacy: .exe fallback registration used by early versions'

    # ---- Installation errors ---------------------------------------------
    'Shell.Error.CreateKeyFailed'        = 'Unable to create the registry key: HKCU\{0} ({1})'
    'Shell.Error.CreateKeyFailedNoDetail' = 'Unable to create the registry key: HKCU\{0}'
    'Shell.Error.PickerMissing'          = 'Menu script not found: {0}. Make sure MenuPicker.ps1 sits in the same folder as PathAdder.ps1.'

    # ---- Uninstall report --------------------------------------------------
    'Shell.Uninstall.RemovedSubtree' = '{0} (entire subtree)'

    # ---- Shell association cache refresh ---------------------------------
    'Shell.Refresh.InteropFailed' = 'Failed to load the shell32 interop assembly; the Explorer refresh was skipped. Please restart Explorer manually or sign out and back in.'
    'Shell.Refresh.Notified'      = 'Notified Explorer to refresh file associations (SHCNE_ASSOCCHANGED + SHCNE_UPDATEITEM).'
    'Shell.Refresh.Failed'        = 'Failed to notify Explorer to refresh (the menu registration result is unaffected): {0} Please restart Explorer manually or sign out and back in.'

    # ---- Confirmation box fallback (no GUI) --------------------------------
    'Shell.Confirm.PrefixedMessage' = '[PATH Assistant] {0}'
    'Shell.Confirm.NoGui'           = '[PATH Assistant] No graphical session is available; answered "No" (Explorer will not be restarted).'
    'Shell.Confirm.BoxFailed'       = '[PATH Assistant] The confirmation box could not be displayed; answered "No" (Explorer will not be restarted).'

    # ---- Explorer restart ---------------------------------------------------
    'Shell.Restart.Success' = 'Explorer has been restarted ({0} explorer process(es) were running).'
    'Shell.Restart.Failed'  = 'Failed to restart Explorer (the menu registration is unaffected): {0}{1}Please run this manually: Stop-Process -Name explorer -Force; Start-Process explorer.exe'
}
