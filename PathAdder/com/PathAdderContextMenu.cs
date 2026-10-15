// -----------------------------------------------------------------------------
// PathAdder classic IContextMenu shell extension - a real POPUP cascade submenu
//
// Why this approach:
//   The IExplorerCommand + ECF_HASSUBCOMMANDS route does not work on this machine.
//   Diagnostics showed Explorer running through
//       GetFlags(ECF_HASSUBCOMMANDS) -> GetTitle -> EnumSubCommands -> enumerator built
//   and then *never* calling IEnumExplorerCommand::Next; instead it creates another
//   object, calls GetState only, and stops. In other words: not a bug in our
//   implementation, Explorer simply does not take that cascade path.
//
//   This component uses the oldest and most reliable Windows technique instead:
//   implement IShellExtInit + IContextMenu, build a submenu HMENU with
//   CreatePopupMenu inside QueryContextMenu, and insert the parent item into
//   Explorer's menu with MF_POPUP. Hover expansion is then handled by the USER32
//   menu system - standard menu behavior that does not depend on any Explorer
//   extension policy. (Mature extensions like TortoiseGit / TortoiseSVN do exactly this.)
//
// Menu layout (command id offsets, 0 is the parent item itself):
//     1  Add to PATH (current user)
//     2  Add to PATH (system-wide, admin)
//     3  Remove from PATH
//     4  -------------------- (separator, clicking it does nothing)
//     5  Open PATH Manager
//
// WARNING: no COM visible method may throw (it would crash the Explorer process).
//   Everything is wrapped in try/catch and returns an HRESULT.
// WARNING: the vtable order must match shobjidl_core.h.
//
// Menu strings come from L10n (embedded table in PathAdderShellExt.cs); the item
// count, order and idCmd offset mapping must never change.
// -----------------------------------------------------------------------------

using System;
using System.Runtime.InteropServices;
using System.Text;

namespace PathAdderShellExt
{
    #region COM interface declarations

    // Must be public: PathAdderContextMenu is public and implements them.
    // A public class cannot implement / inherit internal interfaces or bases (CS0060 / CS0051).
    [ComImport]
    [Guid("000214e8-0000-0000-c000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellExtInit
    {
        [PreserveSig]
        int Initialize(IntPtr pidlFolder, IntPtr pDataObj, IntPtr hkeyProgID);
    }

    [ComImport]
    [Guid("000214e4-0000-0000-c000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IContextMenu
    {
        [PreserveSig]
        int QueryContextMenu(IntPtr hmenu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint uFlags);

        [PreserveSig]
        int InvokeCommand(IntPtr pici);

        [PreserveSig]
        int GetCommandString(IntPtr idCmd, uint uType, IntPtr pReserved, IntPtr pszName, uint cchMax);
    }

    // IDataObject only needs its first method GetData (slot 0 after IUnknown).
    // Omitting the remaining methods does not shift GetData's vtable slot.
    // Used only inside Initialize, so it can be internal - which also lets its
    // parameters (FORMATETC / STGMEDIUM) be internal, avoiding CS0051.
    [ComImport]
    [Guid("0000010e-0000-0000-c000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IDataObjectHead
    {
        [PreserveSig]
        int GetData(ref FORMATETC pformatetcIn, out STGMEDIUM pmedium);
    }

    #endregion

    #region Structures and P/Invoke

    [StructLayout(LayoutKind.Sequential)]
    internal struct FORMATETC
    {
        public ushort cfFormat;
        public IntPtr ptd;
        public uint dwAspect;
        public int lindex;
        public uint tymed;
    }

    // Native layout on x64: tymed(DWORD) + 4 bytes padding + union(pointer) + pUnkForRelease(pointer).
    // The default StructLayout.Sequential aligns IntPtr on 8 bytes, which produces
    // exactly that padding, so this declaration is correct on 64-bit (it is the
    // widely used community declaration).
    [StructLayout(LayoutKind.Sequential)]
    internal struct STGMEDIUM
    {
        public uint tymed;
        public IntPtr unionmedia;
        public IntPtr pUnkForRelease;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct CMINVOKECOMMANDINFO
    {
        public uint cbSize;
        public uint fMask;
        public IntPtr hwnd;
        public IntPtr lpVerb;
        public IntPtr lpParameters;
        public IntPtr lpDirectory;
        public int nShow;
        public uint dwHotKey;
        public IntPtr hIcon;
    }

    // MENUITEMINFOW (80 bytes on x64). hbmpItem sits at the end of the structure,
    // dwItemData is a separate field - they do not form a union. Keep the order.
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct MENUITEMINFO
    {
        public uint cbSize;
        public uint fMask;
        public uint fType;
        public uint fState;
        public uint wID;
        public IntPtr hSubMenu;
        public IntPtr hbmpChecked;
        public IntPtr hbmpUnchecked;
        public IntPtr dwItemData;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string dwTypeData;
        public uint cch;
        public IntPtr hbmpItem;
    }

    internal static class MenuApi
    {
        [DllImport("user32.dll", EntryPoint = "CreatePopupMenu")]
        public static extern IntPtr CreatePopupMenu();

        [DllImport("user32.dll", EntryPoint = "AppendMenuW", CharSet = CharSet.Unicode)]
        public static extern bool AppendMenu(IntPtr hMenu, uint uFlags, IntPtr uIDNewItem, string lpNewItem);

        [DllImport("user32.dll", EntryPoint = "InsertMenuItemW", CharSet = CharSet.Unicode)]
        public static extern bool InsertMenuItem(IntPtr hMenu, uint uItem, bool fByPosition, ref MENUITEMINFO lpmii);

        [DllImport("shell32.dll", EntryPoint = "DragQueryFileW", CharSet = CharSet.Unicode)]
        public static extern uint DragQueryFile(IntPtr hDrop, uint iFile, StringBuilder lpszFile, uint cch);

        [DllImport("ole32.dll")]
        public static extern void ReleaseStgMedium(ref STGMEDIUM pmedium);
    }

    #endregion

    #region Menu command definitions

    internal struct MenuEntry
    {
        public string Title;
        public string Action;   // -Action passed to PathAdder.ps1
        public string Scope;    // -Scope passed to PathAdder.ps1, null means "not passed"
        public bool IsSeparator;
    }

    #endregion

    /// <summary>
    /// "PATH Assistant" context menu (with a real hover-expanding submenu).
    /// CLSID: 9B3E5D2A-7C41-4F8B-A1D6-2E5C8F40B7A3
    /// </summary>
    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("9B3E5D2A-7C41-4F8B-A1D6-2E5C8F40B7A3")]
    [ProgId("PathAdderShellExt.PathAdderContextMenu")]
    public class PathAdderContextMenu : IShellExtInit, IContextMenu
    {
        private const uint CF_HDROP = 15;
        private const uint DVASPECT_CONTENT = 1;
        private const uint TYMED_HGLOBAL = 1;

        // Values taken from the Windows SDK shobjidl_core.h, verified against Microsoft Learn.
        private const uint CMF_DEFAULTONLY = 0x00000001;
        private const uint CMF_OPTIMIZEFORINVOKE = 0x00000800;

        // CMF_RESERVED (0xffff0000) is the mask of "bits that must not be used" (bit16..bit31).
        // WARNING: on this machine Win11 explorer passes 0x20000 - which lands inside the
        //   reserved range - and that very call both inserted the menu and displayed it
        //   correctly. Reserved bits must therefore be IGNORED and never treated as
        //   "do not insert menu items", otherwise the menu simply disappears.
        private const uint CMF_RESERVED = 0xFFFF0000;

        private const uint MF_STRING = 0x00000000;
        private const uint MF_SEPARATOR = 0x00000800;

        private const uint MFT_STRING = 0x00000000;
        private const uint MFS_ENABLED = 0x00000000;

        private const uint MIIM_STATE = 0x00000001;
        private const uint MIIM_ID = 0x00000002;
        private const uint MIIM_SUBMENU = 0x00000004;
        private const uint MIIM_STRING = 0x00000040;

        /// <summary>Full path of the first selected file (captured in Initialize to avoid pointer lifetime issues).</summary>
        private string _target;

        /// <summary>First command id handed out by this QueryContextMenu; also the parent item's own id (offset 0).</summary>
        private uint _idCmdFirst;

        /// <summary>Highest command id actually allocated by this QueryContextMenu (inclusive).
        /// Together with _idCmdFirst it forms the real id range used by InvokeCommand.</summary>
        private uint _idCmdEnd;

        /// <summary>Whether the two values above are usable (only meaningful after QueryContextMenu succeeded).</summary>
        private bool _idsValid;

        /// <summary>Submenu handle. Must stay valid while Explorer shows the menu, so it is
        /// never destroyed here; the process reclaims it on exit (same as common implementations).</summary>
        private IntPtr _hPopup;

        private static MenuEntry[] BuildEntries()
        {
            MenuEntry[] list = new MenuEntry[5];

            list[0].Title = L10n.T("Menu.AddUser");
            list[0].Action = "Add";
            list[0].Scope = "User";
            list[0].IsSeparator = false;

            list[1].Title = L10n.T("Menu.AddSystem");
            list[1].Action = "Add";
            list[1].Scope = "System";
            list[1].IsSeparator = false;

            list[2].Title = L10n.T("Menu.Remove");
            list[2].Action = "Remove";
            list[2].Scope = "All";
            list[2].IsSeparator = false;

            list[3].Title = null;
            list[3].Action = null;
            list[3].Scope = null;
            list[3].IsSeparator = true;

            list[4].Title = L10n.T("Menu.OpenManager");
            list[4].Action = "OpenManager";
            list[4].Scope = null;
            list[4].IsSeparator = false;

            return list;
        }

        // Known flag bits (only used to translate uFlags into readable logs, never in logic)
        private static readonly uint[] KnownFlagMasks = new uint[]
        {
            0x00000001, 0x00000002, 0x00000004, 0x00000008, 0x00000010,
            0x00000020, 0x00000040, 0x00000080, 0x00000100, 0x00000200,
            0x00000400, 0x00000800, 0x00001000, 0x00002000
        };

        private static readonly string[] KnownFlagNames = new string[]
        {
            "DEFAULTONLY", "VERBSONLY", "EXPLORE", "NOVERBS", "CANRENAME",
            "NODEFAULT", "INCLUDESTATIC", "ITEMMENU", "EXTENDEDVERBS", "DISABLEDVERBS",
            "ASYNCVERBSTATE", "OPTIMIZEFORINVOKE", "SYNCCASCADEMENU", "DONOTPICKDEFAULT"
        };

        /// <summary>Translates uFlags into text so the log can be read directly (especially the reserved bits).</summary>
        private static string DescribeFlags(uint uFlags)
        {
            StringBuilder sb = new StringBuilder();
            uint known = 0;

            for (int i = 0; i < KnownFlagMasks.Length; i++)
            {
                uint mask = KnownFlagMasks[i];
                known = known | mask;
                if ((uFlags & mask) != 0)
                {
                    if (sb.Length > 0) { sb.Append('|'); }
                    sb.Append(KnownFlagNames[i]);
                }
            }

            uint reserved = uFlags & CMF_RESERVED;
            if (reserved != 0)
            {
                if (sb.Length > 0) { sb.Append('|'); }
                sb.Append("reserved0x").Append(reserved.ToString("X")).Append("(ignored per spec)");
            }

            uint other = uFlags & ~(known | CMF_RESERVED);
            if (other != 0)
            {
                if (sb.Length > 0) { sb.Append('|'); }
                sb.Append("unknown0x").Append(other.ToString("X"));
            }

            if (sb.Length == 0) { return "none"; }
            return sb.ToString();
        }

        /// <summary>
        /// Resolves Explorer's lpVerb into a command offset for this call (0 = parent itself, 1..n = children).
        ///
        /// Explorer uses two different conventions in practice and both must be handled,
        /// otherwise clicking simply does nothing:
        ///   (1) absolute id: lpVerb falls inside [_idCmdFirst, _idCmdEnd] allocated by this call,
        ///       then offset = lpVerb - _idCmdFirst.
        ///   (2) relative offset: lpVerb is a small integer inside [0, _idCmdEnd - _idCmdFirst],
        ///       and lpVerb *is* the offset.
        ///       This machine does exactly that: clicking child 5 "Open PATH Manager" gives
        ///       lpVerb=5 while _idCmdFirst=31075; the old code computed 5-31075 = -31070,
        ///       the index went out of range and was silently dropped - the direct cause of
        ///       "nothing pops up".
        ///
        /// Matching against the id range this instance really allocated (instead of blindly
        /// subtracting _idCmdFirst) also avoids misreading when InvokeCommand and
        /// QueryContextMenu run on different instances.
        /// </summary>
        /// <param name="rawVerb">Numeric value of CMINVOKECOMMANDINFO.lpVerb.</param>
        /// <param name="entryCount">Number of submenu entries (excluding the parent).</param>
        /// <returns>The resolved offset, or -1 when it cannot be mapped (caller ignores it safely).</returns>
        private int ResolveOffset(long rawVerb, int entryCount)
        {
            // High 16 bits non-zero -> lpVerb is a verb string pointer, unsupported here
            if (rawVerb < 0L || (rawVerb & 0xFFFF0000L) != 0L) { return -1; }

            uint verb = (uint)(rawVerb & 0xFFFFL);

            if (_idsValid)
            {
                if (verb >= _idCmdFirst && verb <= _idCmdEnd)
                {
                    return (int)(verb - _idCmdFirst);      // (1) absolute id
                }

                uint span = _idCmdEnd - _idCmdFirst;       // highest offset used by this call
                if (verb <= span)
                {
                    return (int)verb;                      // (2) relative offset
                }

                return -1;
            }

            // QueryContextMenu never ran successfully (different instance / only Initialize):
            // the only possible reading is a relative offset, and it must be in range;
            // anything out of range is treated as invalid.
            if (verb <= (uint)entryCount) { return (int)verb; }
            return -1;
        }

        #region IShellExtInit

        public int Initialize(IntPtr pidlFolder, IntPtr pDataObj, IntPtr hkeyProgID)
        {
            _target = null;

            try
            {
                if (pDataObj == IntPtr.Zero) { return Native.S_OK; }

                object raw = Marshal.GetObjectForIUnknown(pDataObj);
                IDataObjectHead data = raw as IDataObjectHead;
                if (data == null) { return Native.S_OK; }

                FORMATETC fe = new FORMATETC();
                fe.cfFormat = (ushort)CF_HDROP;
                fe.ptd = IntPtr.Zero;
                fe.dwAspect = DVASPECT_CONTENT;
                fe.lindex = -1;
                fe.tymed = TYMED_HGLOBAL;

                STGMEDIUM stg = new STGMEDIUM();
                if (data.GetData(ref fe, out stg) != Native.S_OK) { return Native.S_OK; }

                // Note: STGMEDIUM must be released in finally regardless of success
                try
                {
                    if (stg.unionmedia == IntPtr.Zero) { return Native.S_OK; }

                    uint count = MenuApi.DragQueryFile(stg.unionmedia, 0xFFFFFFFFu, null, 0);
                    if (count > 0)
                    {
                        StringBuilder sb = new StringBuilder(1024);
                        MenuApi.DragQueryFile(stg.unionmedia, 0u, sb, (uint)sb.Capacity);
                        _target = sb.ToString();
                    }
                }
                finally
                {
                    try { MenuApi.ReleaseStgMedium(ref stg); } catch { }
                }

                Helper.Log("Ctx.Initialize target=" + (_target ?? "(null)"));
                return Native.S_OK;
            }
            catch (Exception ex)
            {
                Helper.Log("Ctx.Initialize exception: " + ex.Message);
                return Native.S_OK;   // a failed init must not block the menu
            }
        }

        #endregion

        #region IContextMenu

        public int QueryContextMenu(IntPtr hmenu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint uFlags)
        {
            try
            {
                _idsValid = false;

                Helper.Log("Ctx.QueryContextMenu flags=0x" + uFlags.ToString("X") +
                           "[" + DescribeFlags(uFlags) + "]" +
                           " idCmdFirst=" + idCmdFirst + " idCmdLast=" + idCmdLast);

                // CMF_DEFAULTONLY: default item only, do not add anything
                if ((uFlags & CMF_DEFAULTONLY) != 0) { return Native.S_OK; }

                // CMF_OPTIMIZEFORINVOKE (0x800): the caller only wants the default verb
                // (typically a double click). The spec explicitly requires handlers that do
                // not support invocation by canonical verb name to skip QueryContextMenu
                // processing - so insert nothing, consume no command ids, and return 0
                // (low 16 bits = number of ids used).
                if ((uFlags & CMF_OPTIMIZEFORINVOKE) != 0)
                {
                    Helper.Log("Ctx. CMF_OPTIMIZEFORINVOKE hit, no menu items inserted, no ids consumed");
                    return Native.S_OK;
                }

                MenuEntry[] entries = BuildEntries();

                // ids needed = 1 for the parent + 1 per child (the separator also takes one, keeping numbering simple)
                uint need = (uint)(entries.Length + 1);
                if ((idCmdLast - idCmdFirst + 1) < need)
                {
                    Helper.Log("Ctx. not enough command ids, skipping");
                    return Native.S_OK;
                }

                uint nextId = idCmdFirst;

                uint parentId = nextId;
                nextId = nextId + 1;

                IntPtr popup = MenuApi.CreatePopupMenu();
                if (popup == IntPtr.Zero)
                {
                    Helper.Log("Ctx.CreatePopupMenu failed");
                    return Native.S_OK;
                }
                _hPopup = popup;

                for (int i = 0; i < entries.Length; i++)
                {
                    if (entries[i].IsSeparator)
                    {
                        MenuApi.AppendMenu(popup, MF_SEPARATOR, new IntPtr((long)nextId), null);
                    }
                    else
                    {
                        MenuApi.AppendMenu(popup, MF_STRING, new IntPtr((long)nextId), entries[i].Title);
                    }
                    nextId = nextId + 1;
                }

                string parentTitle = L10n.T("Menu.Root");

                MENUITEMINFO mii = new MENUITEMINFO();
                mii.cbSize = (uint)Marshal.SizeOf(typeof(MENUITEMINFO));
                mii.fMask = MIIM_SUBMENU | MIIM_STRING | MIIM_ID | MIIM_STATE;
                mii.fType = MFT_STRING;
                mii.fState = MFS_ENABLED;
                mii.wID = parentId;
                mii.hSubMenu = popup;
                mii.dwTypeData = parentTitle;

                bool ok = MenuApi.InsertMenuItem(hmenu, indexMenu, true, ref mii);
                Helper.Log("Ctx.InsertMenuItem -> " + ok + " (parent " + parentTitle +
                           ", children " + entries.Length + ")");

                // The id range only means something to InvokeCommand after a real insert
                _idCmdFirst = idCmdFirst;
                _idCmdEnd = nextId - 1;
                _idsValid = true;
                Helper.Log("Ctx. actual id range: parent=" + _idCmdFirst +
                           " children=[" + (_idCmdFirst + 1) + "," + _idCmdEnd + "]");

                // Return value = how many command ids we consumed (low 16 bits)
                uint used = nextId - idCmdFirst;
                return (int)used;
            }
            catch (Exception ex)
            {
                Helper.Log("Ctx.QueryContextMenu exception: " + ex.Message);
                return 0;
            }
        }

        public int InvokeCommand(IntPtr pici)
        {
            try
            {
                if (pici == IntPtr.Zero) { return Native.E_FAIL; }

                CMINVOKECOMMANDINFO ici =
                    (CMINVOKECOMMANDINFO)Marshal.PtrToStructure(pici, typeof(CMINVOKECOMMANDINFO));

                long rawVerb = ici.lpVerb.ToInt64();

                MenuEntry[] entries = BuildEntries();
                int offset = ResolveOffset(rawVerb, entries.Length);

                Helper.Log("Ctx.InvokeCommand rawVerb=" + rawVerb +
                           " idCmdFirst=" + _idCmdFirst +
                           " idRange=[" + _idCmdFirst + "," + _idCmdEnd + "]" +
                           (_idsValid ? "(valid)" : "(not allocated)") +
                           " -> offset=" + offset +
                           " target=" + (_target ?? "(null)"));

                int idx = offset - 1;          // 0 is the parent itself (POPUP, normally not clickable)
                if (idx < 0 || idx >= entries.Length)
                {
                    Helper.Log("Ctx. offset does not map to an entry, ignoring");
                    return Native.S_OK;
                }

                MenuEntry e = entries[idx];
                if (e.IsSeparator || string.IsNullOrEmpty(e.Action))
                {
                    Helper.Log("Ctx. separator hit (idx=" + idx + "), no action");
                    return Native.S_OK;
                }

                Helper.Log("Ctx. hit [" + idx + "] " + e.Title +
                           " Action=" + e.Action +
                           " Scope=" + (string.IsNullOrEmpty(e.Scope) ? "(not passed)" : e.Scope));

                Helper.Launch(e.Action, e.Scope, _target);
                return Native.S_OK;
            }
            catch (Exception ex)
            {
                Helper.Log("Ctx.InvokeCommand exception: " + ex.Message);
                return Native.E_FAIL;
            }
        }

        public int GetCommandString(IntPtr idCmd, uint uType, IntPtr pReserved, IntPtr pszName, uint cchMax)
        {
            // No status bar help text needed; returning E_NOTIMPL is allowed by the docs
            return Native.E_NOTIMPL;
        }

        #endregion
    }
}
