// -----------------------------------------------------------------------------
// PathAdder COM shell extension - implements a real "hover to expand" cascade menu
//
// Why this file exists:
//   Windows' native static "SubCommands" cascade does not expand on Windows 11
//   (the parent item shows up but nothing happens on hover). This component uses
//   IExplorerCommand + IEnumExplorerCommand so Explorer enumerates the sub commands
//   natively and renders a true hover cascade.
//
// Interface GUIDs come from the Windows SDK (shobjidl_core.h), cross-checked against
// two independent sources (Vanara / ReactOS PSDK):
//   IExplorerCommand      a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9
//   IEnumExplorerCommand  a88826f8-186f-4987-aade-ea0cef8fbfe8
//   IShellItem            43826d1e-e718-42ee-bc55-a1e261c37bfe
//   IShellItemArray       b63ea76d-1f85-456f-a19c-48159efa858b
//
// WARNING: the vtable order must be preserved exactly. Declaring one method too few
//   or too many makes COM calls land on the wrong slot, which shows up as Explorer
//   hanging or crashing and is extremely hard to diagnose.
//
// WARNING: no COM visible method may throw (it would crash the Explorer process).
//   Everything is wrapped in try/catch and returns an HRESULT.
//
// Build (64-bit, must match 64-bit explorer.exe):
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe ^
//     /target:library /platform:x64 /out:PathAdderShellExt.dll PathAdderShellExt.cs
//
// Register (needs elevation):
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\regasm.exe /codebase PathAdderShellExt.dll
//
// Localization: this DLL runs inside explorer.exe and cannot read the PowerShell
//   language packs, so all user-facing strings are embedded here (see L10n below).
//   Developer-facing output (Helper.Log) is always English.
// -----------------------------------------------------------------------------

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

[assembly: ComVisible(true)]
[assembly: Guid("8c1f4a2e-6b3d-4f51-9a7c-2e5d8b4a1c00")]

namespace PathAdderShellExt
{
    #region COM interface declarations

    // IShellItem / IShellItemArray must be public:
    // they appear in the signature of the public interface IExplorerCommand, and
    // declaring them internal produces CS0051 "inconsistent accessibility".
    [ComImport]
    [Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItem
    {
        [PreserveSig] int BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
        [PreserveSig] int GetParent(out IShellItem ppsi);
        [PreserveSig] int GetDisplayName(int sigdnName, out IntPtr ppszName);
        [PreserveSig] int GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        [PreserveSig] int Compare(IShellItem psi, uint hint, out int piOrder);
    }

    [ComImport]
    [Guid("b63ea76d-1f85-456f-a19c-48159efa858b")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItemArray
    {
        [PreserveSig] int BindToHandler(IntPtr pbc, ref Guid rbhid, ref Guid riid, out IntPtr ppvOut);
        [PreserveSig] int GetPropertyStore(int flags, ref Guid riid, out IntPtr ppv);
        [PreserveSig] int GetPropertyDescriptionList(IntPtr keyType, ref Guid riid, out IntPtr ppv);
        [PreserveSig] int GetAttributes(uint dwAttribFlags, uint sfgaoMask, out uint psfgaoAttribs);
        [PreserveSig] int GetCount(out uint pdwNumItems);
        [PreserveSig] int GetItemAt(uint dwIndex, out IShellItem ppsi);
        [PreserveSig] int EnumItems(out IntPtr ppenumShellItems);
    }

    [ComImport]
    [Guid("a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IExplorerCommand
    {
        [PreserveSig] int GetTitle(IShellItemArray psiItemArray, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
        [PreserveSig] int GetIcon(IShellItemArray psiItemArray, [MarshalAs(UnmanagedType.LPWStr)] out string ppszIcon);
        [PreserveSig] int GetToolTip(IShellItemArray psiItemArray, [MarshalAs(UnmanagedType.LPWStr)] out string ppszInfotip);
        [PreserveSig] int GetCanonicalName(out Guid pguidCommandName);
        [PreserveSig] int GetState(IShellItemArray psiItemArray, int fOkToBeSlow, out int pCmdState);
        [PreserveSig] int Invoke(IShellItemArray psiItemArray, IntPtr pbc);
        [PreserveSig] int GetFlags(out int pFlags);
        [PreserveSig] int EnumSubCommands(out IEnumExplorerCommand pEnum);
    }

    [ComImport]
    [Guid("a88826f8-186f-4987-aade-ea0cef8fbfe8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IEnumExplorerCommand
    {
        [PreserveSig]
        int Next(uint celt,
                 [Out, MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.Interface, SizeParamIndex = 0)]
                 IExplorerCommand[] pUICommand,
                 out uint pceltFetched);
        [PreserveSig] int Skip(uint celt);
        void Reset();
        [return: MarshalAs(UnmanagedType.Interface)] IEnumExplorerCommand Clone();
    }

    #endregion

    #region Constants

    internal static class Native
    {
        // SIGDN (SHELLITEMDETAILNAME)
        public const int SIGDN_FILESYSPATH = unchecked((int)0x80058000);

        // EXPCMDSTATE
        public const int ECS_ENABLED = 0x000;
        public const int ECS_DISABLED = 0x001;
        public const int ECS_HIDDEN = 0x002;

        // EXPCMDFLAGS
        public const int ECF_DEFAULT = 0x000;
        public const int ECF_HASSUBCOMMANDS = 0x001;
        public const int ECF_HIDELABEL = 0x004;
        public const int ECF_ISSEPARATOR = 0x008;
        public const int ECF_HASLUASHIELD = 0x010;
        public const int ECF_SEPARATORBEFORE = 0x020;
        public const int ECF_SEPARATORAFTER = 0x040;

        // HRESULT
        public const int S_OK = 0;
        public const int S_FALSE = 1;
        public const int E_NOTIMPL = unchecked((int)0x80004001);
        public const int E_FAIL = unchecked((int)0x80004005);
        public const int E_INVALIDARG = unchecked((int)0x80070057);
    }

    #endregion

    #region Localization

    /// <summary>
    /// Minimal embedded localization table.
    ///
    /// The DLL is loaded by explorer.exe and cannot reach the PowerShell language
    /// packs, so every user-facing string is compiled into the assembly.
    ///
    /// The active language is resolved on every call (never cached in a static
    /// readonly field) so switching languages does not require restarting explorer.
    /// </summary>
    internal static class L10n
    {
        public const string English = "en-US";
        public const string Chinese = "zh-CN";

        private const string DefaultLanguage = English;
        private const string LanguageVariable = "PATHADDER_LANG";
        private const string RegistryKeyPath = @"HKEY_CURRENT_USER\Software\PathAdder";
        private const string RegistryValueName = "Language";

        // index 0 = en-US (default + fallback), index 1 = zh-CN
        private static readonly Dictionary<string, string[]> Map =
            new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            { "Menu.Root",        new string[] { "PATH Assistant",                  "PATH 助手" } },
            { "Menu.AddUser",     new string[] { "Add to PATH (current user)",      "添加到 PATH（当前用户）" } },
            { "Menu.AddSystem",   new string[] { "Add to PATH (system-wide, admin)", "添加到 PATH（系统全局，管理员）" } },
            { "Menu.Remove",      new string[] { "Remove from PATH",                "从 PATH 中移除" } },
            { "Menu.OpenManager", new string[] { "Open PATH Manager",               "打开 PATH 管理器" } },
            { "Tip.Root",         new string[] { "Add this folder to PATH or remove it", "把此程序所在目录加入或移出 PATH" } },
            { "Tip.AddUser",      new string[] { "Write to HKCU\\Environment\\Path", "写入 HKCU\\Environment\\Path" } },
            { "Tip.AddSystem",    new string[] { "Write to HKLM, UAC prompt shown", "写入 HKLM，会弹出 UAC" } },
            { "Tip.Remove",       new string[] { "Remove from both user and system PATH", "同时从用户 PATH 与系统 PATH 移除" } },
            { "Tip.OpenManager",  new string[] { "View PATH, backups and change log", "查看 PATH、备份历史与变更日志" } },
        };

        /// <summary>Translate a key. Unknown keys are returned verbatim.</summary>
        public static string T(string key)
        {
            try
            {
                if (string.IsNullOrEmpty(key)) { return key; }

                string[] values;
                if (!Map.TryGetValue(key, out values)) { return key; }
                if (values == null || values.Length == 0) { return key; }

                int index = string.Equals(CurrentLanguage, Chinese, StringComparison.OrdinalIgnoreCase) ? 1 : 0;
                if (index >= values.Length) { index = 0; }

                string text = values[index];
                return string.IsNullOrEmpty(text) ? key : text;
            }
            catch
            {
                return key;
            }
        }

        /// <summary>
        /// Resolved on every access: env var -&gt; HKCU registry -&gt; UI culture -&gt; en-US.
        /// English is the default; anything unrecognized falls back to en-US.
        /// </summary>
        public static string CurrentLanguage
        {
            get
            {
                try
                {
                    string lang = Normalize(ReadFromEnvironment());
                    if (lang != null) { return lang; }

                    lang = Normalize(ReadFromRegistry());
                    if (lang != null) { return lang; }

                    lang = Normalize(ReadFromUiCulture());
                    if (lang != null) { return lang; }
                }
                catch
                {
                }

                return DefaultLanguage;
            }
        }

        /// <summary>Maps a raw language tag to en-US / zh-CN. English is the default.</summary>
        private static string Normalize(string raw)
        {
            if (string.IsNullOrEmpty(raw)) { return null; }

            string tag = raw.Trim();
            if (tag.Length == 0) { return null; }

            string lower = tag.ToLowerInvariant();
            if (lower == "zh" || lower.StartsWith("zh-", StringComparison.Ordinal) ||
                lower.StartsWith("zh_", StringComparison.Ordinal))
            {
                return Chinese;
            }

            // en / en-* / anything else -> English (the default)
            return English;
        }

        private static string ReadFromEnvironment()
        {
            try
            {
                return Environment.GetEnvironmentVariable(LanguageVariable);
            }
            catch
            {
                return null;
            }
        }

        /// <summary>Reading the registry must never crash explorer, hence the try/catch.</summary>
        private static string ReadFromRegistry()
        {
            try
            {
                object value = Microsoft.Win32.Registry.GetValue(RegistryKeyPath, RegistryValueName, null);
                if (value == null) { return null; }
                return value.ToString();
            }
            catch
            {
                return null;
            }
        }

        private static string ReadFromUiCulture()
        {
            try
            {
                return Thread.CurrentThread.CurrentUICulture.Name;
            }
            catch
            {
                return null;
            }
        }
    }

    #endregion

    #region Helpers

    internal static class Helper
    {
        /// <summary>
        /// Diagnostic log, written to %TEMP%\PathAdderShellExt.log.
        /// Used to confirm that explorer.exe really loaded this DLL and which methods
        /// it called - the only reliable way to tell "never called" apart from
        /// "called but failed" when the cascade menu does not expand.
        /// Note: explorer unloads idle COM DLLs after the menu closes, so "the DLL is
        /// not in the module list" is not evidence that it was never loaded.
        /// Messages are always English (developer-facing).
        /// </summary>
        public static void Log(string message)
        {
            try
            {
                string path = Path.Combine(Path.GetTempPath(), "PathAdderShellExt.log");
                string line = DateTime.Now.ToString("HH:mm:ss.fff") + " pid=" +
                              Process.GetCurrentProcess().Id + "  " + message;
                File.AppendAllText(path, line + Environment.NewLine);
            }
            catch { }
        }

        /// <summary>Returns the full path of the first selected item; null on failure. Never throws.</summary>
        public static string GetFirstPath(IShellItemArray items)
        {
            try
            {
                if (items == null) return null;

                uint count;
                int hr = items.GetCount(out count);
                if (hr != Native.S_OK || count == 0) return null;

                IShellItem item;
                hr = items.GetItemAt(0, out item);
                if (hr != Native.S_OK || item == null) return null;

                IntPtr ptr;
                hr = item.GetDisplayName(Native.SIGDN_FILESYSPATH, out ptr);
                if (hr != Native.S_OK || ptr == IntPtr.Zero) return null;

                try { return Marshal.PtrToStringUni(ptr); }
                finally { Marshal.FreeCoTaskMem(ptr); }
            }
            catch { return null; }
        }

        /// <summary>Locates PathAdder.ps1 (same directory as this DLL, or one level up).</summary>
        public static string GetEnginePath()
        {
            try
            {
                string asmDir = Path.GetDirectoryName(typeof(Helper).Assembly.Location);
                if (string.IsNullOrEmpty(asmDir)) return null;

                // This DLL lives under com\, the engine sits one level up
                string candidate = Path.Combine(asmDir, "PathAdder.ps1");
                if (File.Exists(candidate)) return candidate;

                string parent = Directory.GetParent(asmDir).FullName;
                candidate = Path.Combine(parent, "PathAdder.ps1");
                if (File.Exists(candidate)) return candidate;

                return null;
            }
            catch { return null; }
        }

        /// <summary>Launches PowerShell to run an action. Non-blocking, never throws.</summary>
        public static void Launch(string action, string scope, string target)
        {
            try
            {
                string engine = GetEnginePath();
                if (string.IsNullOrEmpty(engine)) return;

                var sb = new StringBuilder();
                sb.Append("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"")
                  .Append(engine).Append('"');
                sb.Append(" -Action ").Append(action);
                if (!string.IsNullOrEmpty(scope)) sb.Append(" -Scope ").Append(scope);
                if (!string.IsNullOrEmpty(target)) sb.Append(" -Target \"").Append(target).Append('"');

                // Pass the resolved UI language down to PathAdder.ps1
                sb.Append(" -Language \"").Append(L10n.CurrentLanguage).Append('"');

                var psi = new ProcessStartInfo("powershell.exe", sb.ToString());
                psi.UseShellExecute = true;          // required, see project notes: Start-Process fails on duplicate env var keys
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                psi.CreateNoWindow = true;
                Process.Start(psi);
            }
            catch { }
        }
    }

    #endregion

    #region Parent command

    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("1C789ABD-65D1-5FAD-8B98-52595EBB290B")]
    public class PathAdderCommand : IExplorerCommand
    {
        public PathAdderCommand()
        {
            Helper.Log("PathAdderCommand ctor (explorer created the COM object successfully)");
        }

        public int GetTitle(IShellItemArray psiItemArray, out string ppszName)
        {
            Helper.Log("Parent.GetTitle");
            ppszName = L10n.T("Menu.Root");
            return Native.S_OK;
        }

        public int GetIcon(IShellItemArray psiItemArray, out string ppszIcon)
        {
            ppszIcon = "imageres.dll,-5303";
            return Native.S_OK;
        }

        public int GetToolTip(IShellItemArray psiItemArray, out string ppszInfotip)
        {
            ppszInfotip = L10n.T("Tip.Root");
            return Native.S_OK;
        }

        public int GetCanonicalName(out Guid pguidCommandName)
        {
            pguidCommandName = new Guid("1C789ABD-65D1-5FAD-8B98-52595EBB290B");
            return Native.S_OK;
        }

        public int GetState(IShellItemArray psiItemArray, int fOkToBeSlow, out int pCmdState)
        {
            Helper.Log("Parent.GetState");
            pCmdState = Native.ECS_ENABLED;
            return Native.S_OK;
        }

        /// <summary>Parent clicked: cascade parents normally do nothing on click.</summary>
        public int Invoke(IShellItemArray psiItemArray, IntPtr pbc)
        {
            Helper.Log("Parent.Invoke (reaching here means Explorer did not treat it as a cascade parent)");
            return Native.S_OK;
        }

        /// <summary>Key part: declaring sub commands is what makes Explorer enumerate and expand on hover.</summary>
        public int GetFlags(out int pFlags)
        {
            pFlags = Native.ECF_HASSUBCOMMANDS;
            Helper.Log("Parent.GetFlags -> ECF_HASSUBCOMMANDS(1)");
            return Native.S_OK;
        }

        public int EnumSubCommands(out IEnumExplorerCommand pEnum)
        {
            Helper.Log("Parent.EnumSubCommands called");
            try
            {
                pEnum = new SubCommandEnum();
                Helper.Log("Parent.EnumSubCommands -> enumerator OK");
                return Native.S_OK;
            }
            catch (Exception ex)
            {
                Helper.Log("Parent.EnumSubCommands exception: " + ex.Message);
                pEnum = null;
                return Native.E_FAIL;
            }
        }
    }

    #endregion

    #region Sub commands

    // Must be public: derived classes (AddUserCommand etc.) are public and COM
    // activated, and a public class cannot derive from an internal base (CS0060).
    // ComVisible(false) keeps regasm from exporting the abstract base itself.
    [ComVisible(false)]
    public abstract class LeafCommand : IExplorerCommand
    {
        protected abstract string Title { get; }
        protected abstract string ToolTip { get; }
        protected abstract Guid CanonicalName { get; }
        protected abstract int Flags { get; }
        protected abstract string Action { get; }
        protected abstract string Scope { get; }   // null means "not passed"

        public int GetTitle(IShellItemArray psiItemArray, out string ppszName)
        {
            ppszName = Title;
            Helper.Log("  Leaf.GetTitle -> " + Title);
            return Native.S_OK;
        }

        public int GetIcon(IShellItemArray psiItemArray, out string ppszIcon)
        {
            // Documented convention: return E_NOTIMPL when there is no icon
            // (returning E_FAIL makes some hosts still read ppszIcon, and reading a
            // null can trigger an access violation).
            ppszIcon = null;
            return Native.E_NOTIMPL;
        }

        public int GetToolTip(IShellItemArray psiItemArray, out string ppszInfotip)
        {
            ppszInfotip = ToolTip;
            return Native.S_OK;
        }

        public int GetCanonicalName(out Guid pguidCommandName)
        {
            pguidCommandName = CanonicalName;
            return Native.S_OK;
        }

        public int GetState(IShellItemArray psiItemArray, int fOkToBeSlow, out int pCmdState)
        {
            pCmdState = Native.ECS_ENABLED;
            return Native.S_OK;
        }

        public int GetFlags(out int pFlags)
        {
            pFlags = Flags;
            return Native.S_OK;
        }

        public int EnumSubCommands(out IEnumExplorerCommand pEnum)
        {
            pEnum = null;
            return Native.E_NOTIMPL;   // leaf nodes have no sub commands
        }

        /// <summary>
        /// Must be virtual: the interface mapping is bound on LeafCommand, so if a
        /// subclass hides it with "new", COM still calls the base implementation
        /// (the separator would then fire PowerShell once).
        /// </summary>
        public virtual int Invoke(IShellItemArray psiItemArray, IntPtr pbc)
        {
            try
            {
                string target = Helper.GetFirstPath(psiItemArray);
                Helper.Log("  Leaf.Invoke Action=" + Action + " Scope=" + Scope + " target=" + (target ?? "(null)"));
                Helper.Launch(Action, Scope, target);
                return Native.S_OK;
            }
            catch (Exception ex)
            {
                Helper.Log("  Leaf.Invoke exception: " + ex.Message);
                return Native.E_FAIL;
            }
        }
    }

    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("A7E4EA78-559F-5293-A8AF-A4EC698FA7DC")]
    public class AddUserCommand : LeafCommand
    {
        protected override string Title { get { return L10n.T("Menu.AddUser"); } }
        protected override string ToolTip { get { return L10n.T("Tip.AddUser"); } }
        protected override Guid CanonicalName { get { return new Guid("A7E4EA78-559F-5293-A8AF-A4EC698FA7DC"); } }
        protected override int Flags { get { return Native.ECF_DEFAULT; } }
        protected override string Action { get { return "Add"; } }
        protected override string Scope { get { return "User"; } }
    }

    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("0674C9EF-7F6F-5C43-AA8B-36DCC81637B6")]
    public class AddSystemCommand : LeafCommand
    {
        protected override string Title { get { return L10n.T("Menu.AddSystem"); } }
        protected override string ToolTip { get { return L10n.T("Tip.AddSystem"); } }
        protected override Guid CanonicalName { get { return new Guid("0674C9EF-7F6F-5C43-AA8B-36DCC81637B6"); } }
        protected override int Flags { get { return Native.ECF_HASLUASHIELD; } }  // shows the UAC shield
        protected override string Action { get { return "Add"; } }
        protected override string Scope { get { return "System"; } }
    }

    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("124AC498-75CF-5595-B46B-2CEFD81211A4")]
    public class RemoveCommand : LeafCommand
    {
        protected override string Title { get { return L10n.T("Menu.Remove"); } }
        protected override string ToolTip { get { return L10n.T("Tip.Remove"); } }
        protected override Guid CanonicalName { get { return new Guid("124AC498-75CF-5595-B46B-2CEFD81211A4"); } }
        protected override int Flags { get { return Native.ECF_DEFAULT; } }
        protected override string Action { get { return "Remove"; } }
        protected override string Scope { get { return "All"; } }
    }

    /// <summary>Pure separator entry.</summary>
    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("4B5172F7-E928-506A-BABA-DFD251355925")]
    public class SeparatorCommand : LeafCommand
    {
        protected override string Title { get { return ""; } }
        protected override string ToolTip { get { return ""; } }
        protected override Guid CanonicalName { get { return new Guid("4B5172F7-E928-506A-BABA-DFD251355925"); } }
        protected override int Flags { get { return Native.ECF_ISSEPARATOR; } }
        protected override string Action { get { return "None"; } }
        protected override string Scope { get { return null; } }

        /// <summary>Separators ignore clicks (override, not new - otherwise the interface mapping still points at the base).</summary>
        public override int Invoke(IShellItemArray psiItemArray, IntPtr pbc)
        {
            return Native.S_OK;
        }
    }

    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("9921ED8D-5AAF-563A-BAF4-0276A003291B")]
    public class ManagerCommand : LeafCommand
    {
        protected override string Title { get { return L10n.T("Menu.OpenManager"); } }
        protected override string ToolTip { get { return L10n.T("Tip.OpenManager"); } }
        protected override Guid CanonicalName { get { return new Guid("9921ED8D-5AAF-563A-BAF4-0276A003291B"); } }
        protected override int Flags { get { return Native.ECF_DEFAULT; } }
        protected override string Action { get { return "OpenManager"; } }
        protected override string Scope { get { return null; } }
    }

    #endregion

    #region Sub command enumerator

    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("53E97A7A-9ECB-5EC8-8499-CE6030C691BB")]
    public class SubCommandEnum : IEnumExplorerCommand
    {
        private int _index = 0;

        public SubCommandEnum()
        {
            Helper.Log("  SubCommandEnum ctor");
        }

        private static IExplorerCommand[] Build()
        {
            return new IExplorerCommand[]
            {
                new AddUserCommand(),
                new AddSystemCommand(),
                new RemoveCommand(),
                new SeparatorCommand(),
                new ManagerCommand()
            };
        }

        public int Next(uint celt, IExplorerCommand[] pUICommand, out uint pceltFetched)
        {
            pceltFetched = 0;
            Helper.Log("  SubCommandEnum.Next celt=" + celt +
                       " array=" + (pUICommand == null ? "null" : pUICommand.Length.ToString()));
            try
            {
                if (pUICommand == null || pUICommand.Length < celt)
                {
                    Helper.Log("  Next -> E_INVALIDARG (array too small)");
                    return Native.E_INVALIDARG;
                }

                IExplorerCommand[] all = Build();
                uint fetched = 0;
                while (fetched < celt && _index < all.Length)
                {
                    Helper.Log("  Next produced [" + _index + "] " + all[_index].GetType().Name);
                    pUICommand[fetched] = all[_index];
                    _index++;
                    fetched++;
                }

                pceltFetched = fetched;
                Helper.Log("  Next -> fetched " + fetched + ", hr=" +
                           ((fetched == celt) ? "S_OK" : "S_FALSE"));
                return (fetched == celt) ? Native.S_OK : Native.S_FALSE;
            }
            catch (Exception ex)
            {
                Helper.Log("  Next exception: " + ex.GetType().Name + " " + ex.Message);
                return Native.E_FAIL;
            }
        }

        public int Skip(uint celt)
        {
            Helper.Log("  SubCommandEnum.Skip celt=" + celt);
            try { _index += (int)celt; return Native.S_OK; }
            catch { return Native.E_FAIL; }
        }

        public void Reset()
        {
            Helper.Log("  SubCommandEnum.Reset (Explorer started reading the sub menu)");
            _index = 0;
        }

        public IEnumExplorerCommand Clone()
        {
            Helper.Log("  SubCommandEnum.Clone");
            try { return new SubCommandEnum(); }
            catch { return null; }
        }
    }

    #endregion
}
