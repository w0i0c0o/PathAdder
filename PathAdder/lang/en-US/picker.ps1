# -----------------------------------------------------------------------------
# PathAdder language pack - English (United States) - shard: picker
#
# Owner module: MenuPicker.ps1 (click-popup fallback menu) | Picker.*
# Placeholders use .NET composite format: {0} {1} ...
#
# IMPORTANT: this shard only feeds the popup menu that MenuPicker.ps1 shows.
# The shell context menu built from the registry is a different surface and uses
# the Shell.* keys in shell.ps1.
# -----------------------------------------------------------------------------

$PathAdderStrings = @{
    # ---- Menu items (one-to-one with Shell.Verb.*) -----------------------
    'Picker.Item.AddUser'     = 'Add to PATH (current user)'
    'Picker.Item.AddSystem'   = 'Add to PATH (system-wide, administrator)'
    'Picker.Item.Remove'      = 'Remove this folder from PATH'
    'Picker.Item.OpenManager' = 'Open PATH Manager'

    # ---- Errors ----------------------------------------------------------
    'Picker.Error.FormsLoadFailed' = 'Failed to load the Windows.Forms assemblies, so the PATH Assistant menu cannot start: {0}'
    'Picker.Error.EngineMissing'   = 'PathAdder.ps1 was not found - the script has been moved or is corrupted.{0}{0}Expected location: {1}'
    'Picker.Error.ShowFailed'      = 'Failed to display the menu: {0}'
    'Picker.Error.ExecuteFailed'   = 'Execution failed: {0}'
}
