// -----------------------------------------------------------------------------
// PathAdder 经典 IContextMenu 外壳扩展 —— 用真正的 POPUP 子菜单实现悬停级联
//
// 为什么换这条路：
//   IExplorerCommand + ECF_HASSUBCOMMANDS 的方案实测在这台机器上行不通。
//   诊断日志显示 Explorer 走完了
//       GetFlags(ECF_HASSUBCOMMANDS) → GetTitle → EnumSubCommands → 枚举器构造成功
//   之后【永远不会】调用 IEnumExplorerCommand::Next，而是再造一个对象只调 GetState
//   就结束。也就是说：不是我们的实现有 bug，是 Explorer 没有走这条级联路径。
//
//   本组件改用 Windows 最经典、也是最可靠的做法：实现 IShellExtInit + IContextMenu，
//   在 QueryContextMenu 里用 CreatePopupMenu 造一个子菜单 HMENU，再把父项以
//   MF_POPUP 形式插进 Explorer 的菜单里。子菜单的悬停展开由 USER32 的菜单系统
//   负责，是标准菜单行为，不依赖 Explorer 的任何扩展策略。
//   （TortoiseGit / TortoiseSVN 等成熟外壳扩展就是这么做的。）
//
// 菜单结构（命令 id 偏移，0 是父项自身）：
//     1  添加到 PATH（当前用户）
//     2  添加到 PATH（系统全局，管理员）
//     3  从 PATH 中移除此目录
//     4  ──────────────（分隔线，点了不做事）
//     5  打开 PATH 管理器
//
// ⚠ 所有 COM 可见方法都不得抛异常（Explorer 进程会崩），一律 try/catch 并返回 HRESULT。
// ⚠ vtable 顺序必须与 shobjidl_core.h 一致。
// -----------------------------------------------------------------------------

using System;
using System.Runtime.InteropServices;
using System.Text;

namespace PathAdderShellExt
{
    #region COM 接口声明

    // 必须是 public：PathAdderContextMenu 是 public 且要实现它们。
    // public 类不能实现 / 继承 internal 接口或基类（CS0060 / CS0051）。
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

    // IDataObject 只需要第一个方法 GetData（排在 IUnknown 之后的第 0 个）。
    // 后面的方法不声明也不会影响 GetData 的 vtable 槽位。
    // 只在 Initialize 内部使用，因此可以是 internal —— 这样它的参数
    // （FORMATETC / STGMEDIUM）也可以是 internal，避开 CS0051。
    [ComImport]
    [Guid("0000010e-0000-0000-c000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IDataObjectHead
    {
        [PreserveSig]
        int GetData(ref FORMATETC pformatetcIn, out STGMEDIUM pmedium);
    }

    #endregion

    #region 结构与 P/Invoke

    [StructLayout(LayoutKind.Sequential)]
    internal struct FORMATETC
    {
        public ushort cfFormat;
        public IntPtr ptd;
        public uint dwAspect;
        public int lindex;
        public uint tymed;
    }

    // x64 上的原生布局：tymed(DWORD) + 4 字节填充 + union(指针) + pUnkForRelease(指针)。
    // 默认 StructLayout.Sequential 会把 IntPtr 按 8 字节对齐，正好天然补出这段填充，
    // 所以下面这个写法在 64 位下是正确的（社区里广泛使用的声明）。
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

    // MENUITEMINFOW（x64 共 80 字节）。hbmpItem 在结构末尾，
    // dwItemData 是独立字段，两者不构成 union —— 顺序别写错。
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

    #region 菜单命令定义

    internal struct MenuEntry
    {
        public string Title;
        public string Action;   // 传给 PathAdder.ps1 的 -Action
        public string Scope;    // 传给 PathAdder.ps1 的 -Scope，null 表示不传
        public bool IsSeparator;
    }

    #endregion

    /// <summary>
    /// 「PATH 助手」上下文菜单（带真正的悬停展开子菜单）。
    /// CLSID：9B3E5D2A-7C41-4F8B-A1D6-2E5C8F40B7A3
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

        private const uint CMF_DEFAULTONLY = 0x00000001;

        private const uint MF_STRING = 0x00000000;
        private const uint MF_SEPARATOR = 0x00000800;

        private const uint MFT_STRING = 0x00000000;
        private const uint MFS_ENABLED = 0x00000000;

        private const uint MIIM_STATE = 0x00000001;
        private const uint MIIM_ID = 0x00000002;
        private const uint MIIM_SUBMENU = 0x00000004;
        private const uint MIIM_STRING = 0x00000040;

        private const string PARENT_TITLE = "PATH 助手";

        /// <summary>第一个被选中文件的完整路径（Initialize 时就取好，避免指针生命周期问题）。</summary>
        private string _target;

        private uint _idCmdFirst;

        /// <summary>子菜单句柄。Explorer 显示菜单期间必须保持有效，所以这里不主动销毁，
        /// 由进程退出时统一回收（与业界常见的实现方式一致）。</summary>
        private IntPtr _hPopup;

        private static MenuEntry[] BuildEntries()
        {
            MenuEntry[] list = new MenuEntry[5];

            list[0].Title = "添加到 PATH（当前用户）";
            list[0].Action = "Add";
            list[0].Scope = "User";
            list[0].IsSeparator = false;

            list[1].Title = "添加到 PATH（系统全局，管理员）";
            list[1].Action = "Add";
            list[1].Scope = "System";
            list[1].IsSeparator = false;

            list[2].Title = "从 PATH 中移除此目录";
            list[2].Action = "Remove";
            list[2].Scope = "All";
            list[2].IsSeparator = false;

            list[3].Title = null;
            list[3].Action = null;
            list[3].Scope = null;
            list[3].IsSeparator = true;

            list[4].Title = "打开 PATH 管理器";
            list[4].Action = "OpenManager";
            list[4].Scope = null;
            list[4].IsSeparator = false;

            return list;
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

                // 注意：不管成功失败都要走到 finally 释放 STGMEDIUM
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

                Helper.Log("Ctx.Initialize 目标=" + (_target ?? "(null)"));
                return Native.S_OK;
            }
            catch (Exception ex)
            {
                Helper.Log("Ctx.Initialize 异常: " + ex.Message);
                return Native.S_OK;   // 初始化失败也不阻断菜单显示
            }
        }

        #endregion

        #region IContextMenu

        public int QueryContextMenu(IntPtr hmenu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint uFlags)
        {
            try
            {
                Helper.Log("Ctx.QueryContextMenu flags=0x" + uFlags.ToString("X") +
                           " idCmdFirst=" + idCmdFirst + " idCmdLast=" + idCmdLast);

                // CMF_DEFAULTONLY：只建默认项，这种情况下不要加东西
                if ((uFlags & CMF_DEFAULTONLY) != 0) { return Native.S_OK; }

                MenuEntry[] entries = BuildEntries();

                // 需要的 id 数量 = 父项 1 个 + 每个子项 1 个（分隔线也占位，保持编号简单）
                uint need = (uint)(entries.Length + 1);
                if ((idCmdLast - idCmdFirst + 1) < need)
                {
                    Helper.Log("Ctx. id 区间不足，跳过");
                    return Native.S_OK;
                }

                _idCmdFirst = idCmdFirst;
                uint nextId = idCmdFirst;

                uint parentId = nextId;
                nextId = nextId + 1;

                IntPtr popup = MenuApi.CreatePopupMenu();
                if (popup == IntPtr.Zero)
                {
                    Helper.Log("Ctx.CreatePopupMenu 失败");
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

                MENUITEMINFO mii = new MENUITEMINFO();
                mii.cbSize = (uint)Marshal.SizeOf(typeof(MENUITEMINFO));
                mii.fMask = MIIM_SUBMENU | MIIM_STRING | MIIM_ID | MIIM_STATE;
                mii.fType = MFT_STRING;
                mii.fState = MFS_ENABLED;
                mii.wID = parentId;
                mii.hSubMenu = popup;
                mii.dwTypeData = PARENT_TITLE;

                bool ok = MenuApi.InsertMenuItem(hmenu, indexMenu, true, ref mii);
                Helper.Log("Ctx.InsertMenuItem -> " + ok + "（父项 " + PARENT_TITLE +
                           "，子项 " + entries.Length + " 条）");

                // 返回值 = 我们占用了多少个命令 id（低 16 位）
                uint used = nextId - idCmdFirst;
                return (int)used;
            }
            catch (Exception ex)
            {
                Helper.Log("Ctx.QueryContextMenu 异常: " + ex.Message);
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
                if ((rawVerb & 0xFFFF0000L) != 0)
                {
                    // 字符串形式的 verb，本扩展不支持
                    return Native.E_FAIL;
                }

                int offset = (int)(rawVerb & 0xFFFFL) - (int)_idCmdFirst;

                Helper.Log("Ctx.InvokeCommand offset=" + offset + " 目标=" + (_target ?? "(null)"));

                MenuEntry[] entries = BuildEntries();
                int idx = offset - 1;          // 0 号是父项自身（POPUP，正常不会被点到）
                if (idx < 0 || idx >= entries.Length) { return Native.S_OK; }

                MenuEntry e = entries[idx];
                if (e.IsSeparator || string.IsNullOrEmpty(e.Action)) { return Native.S_OK; }

                Helper.Launch(e.Action, e.Scope, _target);
                return Native.S_OK;
            }
            catch (Exception ex)
            {
                Helper.Log("Ctx.InvokeCommand 异常: " + ex.Message);
                return Native.E_FAIL;
            }
        }

        public int GetCommandString(IntPtr idCmd, uint uType, IntPtr pReserved, IntPtr pszName, uint cchMax)
        {
            // 不需要提供状态栏提示文本，返回 E_NOTIMPL 是文档允许的
            return Native.E_NOTIMPL;
        }

        #endregion
    }
}
