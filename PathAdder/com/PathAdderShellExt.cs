// -----------------------------------------------------------------------------
// PathAdder COM 外壳扩展 —— 实现真正的「悬停展开」级联子菜单
//
// 为什么需要它：
//   Windows 原生的 SubCommands 静态级联在 Windows 11 上实测不展开（父项可见、
//   悬停无反应），本组件改用 IExplorerCommand + IEnumExplorerCommand 由 Explorer
//   原生枚举子命令，从而实现真正的悬停级联。
//
// 接口 GUID 均取自 Windows SDK (shobjidl_core.h)，已与 Vanara / ReactOS PSDK
// 两个独立来源交叉核对：
//   IExplorerCommand      a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9
//   IEnumExplorerCommand  a88826f8-186f-4987-aade-ea0cef8fbfe8
//   IShellItem            43826d1e-e718-42ee-bc55-a1e261c37bfe
//   IShellItemArray       b63ea76d-1f85-456f-a19c-48159efa858b
//
// ⚠ vtable 顺序必须严格保持，少声明或多声明一个方法都会让 COM 调用打到错误的
//   槽位上，表现为 Explorer 无响应或直接崩溃，且极难排查。
//
// ⚠ 所有 COM 可见方法都不得抛出异常（会让 Explorer 进程崩溃），一律 try/catch
//   并返回 HRESULT。
//
// 编译（64 位，必须匹配 64 位 explorer.exe）：
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe ^
//     /target:library /platform:x64 /out:PathAdderShellExt.dll PathAdderShellExt.cs
//
// 注册（需管理员）：
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\regasm.exe /codebase PathAdderShellExt.dll
// -----------------------------------------------------------------------------

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

[assembly: ComVisible(true)]
[assembly: Guid("8c1f4a2e-6b3d-4f51-9a7c-2e5d8b4a1c00")]

namespace PathAdderShellExt
{
    #region COM 接口声明

    // IShellItem / IShellItemArray 必须是 public：
    // 它们出现在 public 接口 IExplorerCommand 的方法签名上，若声明为 internal
    // 会产生 CS0051「可访问性不一致」编译错误。
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

    #region 常量

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

    #region 辅助

    internal static class Helper
    {
        /// <summary>
        /// 诊断日志。写到 %TEMP%\PathAdderShellExt.log。
        /// 用于确认 explorer.exe 是否真的加载了本 DLL、调用了哪些方法 —— 
        /// 这是排查「菜单不展开」时唯一可靠的手段（GUI 现象无法区分
        /// 「从未调用」和「调用了但失败」）。
        /// 注意：explorer 会在菜单关闭后卸载空闲的 COM DLL，因此
        /// 「模块列表里看不到本 DLL」不能作为「从未加载」的证据。
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

        /// <summary>取第一个被选中文件的完整路径；失败返回 null。绝不抛异常。</summary>
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

        /// <summary>定位 PathAdder.ps1（与本 DLL 同级目录的上一级）。</summary>
        public static string GetEnginePath()
        {
            try
            {
                string asmDir = Path.GetDirectoryName(typeof(Helper).Assembly.Location);
                if (string.IsNullOrEmpty(asmDir)) return null;

                // 本 DLL 放在 com\ 下，引擎在上一级
                string candidate = Path.Combine(asmDir, "PathAdder.ps1");
                if (File.Exists(candidate)) return candidate;

                string parent = Directory.GetParent(asmDir).FullName;
                candidate = Path.Combine(parent, "PathAdder.ps1");
                if (File.Exists(candidate)) return candidate;

                return null;
            }
            catch { return null; }
        }

        /// <summary>启动 PowerShell 执行动作，不阻塞、不抛异常。</summary>
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

                var psi = new ProcessStartInfo("powershell.exe", sb.ToString());
                psi.UseShellExecute = true;          // 必须，见项目备忘：环境变量键重复时 Start-Process 会失败
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                psi.CreateNoWindow = true;
                Process.Start(psi);
            }
            catch { }
        }
    }

    #endregion

    #region 父菜单命令

    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("1C789ABD-65D1-5FAD-8B98-52595EBB290B")]
    public class PathAdderCommand : IExplorerCommand
    {
        public PathAdderCommand()
        {
            Helper.Log("PathAdderCommand 构造（说明 explorer 已成功创建 COM 对象）");
        }

        public int GetTitle(IShellItemArray psiItemArray, out string ppszName)
        {
            Helper.Log("父.GetTitle");
            ppszName = "PATH 助手";
            return Native.S_OK;
        }

        public int GetIcon(IShellItemArray psiItemArray, out string ppszIcon)
        {
            ppszIcon = "imageres.dll,-5303";
            return Native.S_OK;
        }

        public int GetToolTip(IShellItemArray psiItemArray, out string ppszInfotip)
        {
            ppszInfotip = "把此程序所在目录加入或移出 PATH";
            return Native.S_OK;
        }

        public int GetCanonicalName(out Guid pguidCommandName)
        {
            pguidCommandName = new Guid("1C789ABD-65D1-5FAD-8B98-52595EBB290B");
            return Native.S_OK;
        }

        public int GetState(IShellItemArray psiItemArray, int fOkToBeSlow, out int pCmdState)
        {
            Helper.Log("父.GetState");
            pCmdState = Native.ECS_ENABLED;
            return Native.S_OK;
        }

        /// <summary>父项被点击：级联菜单通常不响应点击，保持无动作即可。</summary>
        public int Invoke(IShellItemArray psiItemArray, IntPtr pbc)
        {
            Helper.Log("父.Invoke（若走到这里，说明 Explorer 没把它当级联父项）");
            return Native.S_OK;
        }

        /// <summary>关键：声明自己有子命令，Explorer 才会去枚举并悬停展开。</summary>
        public int GetFlags(out int pFlags)
        {
            pFlags = Native.ECF_HASSUBCOMMANDS;
            Helper.Log("父.GetFlags -> ECF_HASSUBCOMMANDS(1)");
            return Native.S_OK;
        }

        public int EnumSubCommands(out IEnumExplorerCommand pEnum)
        {
            Helper.Log("父.EnumSubCommands 被调用");
            try
            {
                pEnum = new SubCommandEnum();
                Helper.Log("父.EnumSubCommands -> 返回枚举器 OK");
                return Native.S_OK;
            }
            catch (Exception ex)
            {
                Helper.Log("父.EnumSubCommands 异常: " + ex.Message);
                pEnum = null;
                return Native.E_FAIL;
            }
        }
    }

    #endregion

    #region 子命令

    // 必须是 public：派生类（AddUserCommand 等）是 public 且要被 COM 激活，
    // public 类不能继承 internal 基类（CS0060 可访问性不一致）。
    // 但标记 ComVisible(false)，避免这个抽象基类本身被 regasm 导出。
    [ComVisible(false)]
    public abstract class LeafCommand : IExplorerCommand
    {
        protected abstract string Title { get; }
        protected abstract string ToolTip { get; }
        protected abstract Guid CanonicalName { get; }
        protected abstract int Flags { get; }
        protected abstract string Action { get; }
        protected abstract string Scope { get; }   // null 表示不传

        public int GetTitle(IShellItemArray psiItemArray, out string ppszName)
        {
            ppszName = Title;
            Helper.Log("  子.GetTitle -> " + Title);
            return Native.S_OK;
        }

        public int GetIcon(IShellItemArray psiItemArray, out string ppszIcon)
        {
            // 文档约定：无图标时应返回 E_NOTIMPL（返回 E_FAIL 时部分宿主会
            // 继续读取 ppszIcon，读到 null 有触发访问冲突的风险）。
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
            return Native.E_NOTIMPL;   // 叶子节点没有子命令
        }

        /// <summary>
        /// 必须是 virtual：接口映射绑定在基类 LeafCommand 上，若子类用 new 隐藏，
        /// COM 调用的仍是基类实现（分隔符就会误触发一次 PowerShell）。
        /// </summary>
        public virtual int Invoke(IShellItemArray psiItemArray, IntPtr pbc)
        {
            try
            {
                string target = Helper.GetFirstPath(psiItemArray);
                Helper.Log("  子.Invoke Action=" + Action + " Scope=" + Scope + " 目标=" + (target ?? "(null)"));
                Helper.Launch(Action, Scope, target);
                return Native.S_OK;
            }
            catch (Exception ex)
            {
                Helper.Log("  子.Invoke 异常: " + ex.Message);
                return Native.E_FAIL;
            }
        }
    }

    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("A7E4EA78-559F-5293-A8AF-A4EC698FA7DC")]
    public class AddUserCommand : LeafCommand
    {
        protected override string Title { get { return "添加到 PATH（当前用户）"; } }
        protected override string ToolTip { get { return "写入 HKCU\\Environment\\Path"; } }
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
        protected override string Title { get { return "添加到 PATH（系统全局，管理员）"; } }
        protected override string ToolTip { get { return "写入 HKLM，会弹出 UAC"; } }
        protected override Guid CanonicalName { get { return new Guid("0674C9EF-7F6F-5C43-AA8B-36DCC81637B6"); } }
        protected override int Flags { get { return Native.ECF_HASLUASHIELD; } }  // 显示 UAC 盾牌
        protected override string Action { get { return "Add"; } }
        protected override string Scope { get { return "System"; } }
    }

    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("124AC498-75CF-5595-B46B-2CEFD81211A4")]
    public class RemoveCommand : LeafCommand
    {
        protected override string Title { get { return "从 PATH 中移除此目录"; } }
        protected override string ToolTip { get { return "同时从用户 PATH 与系统 PATH 移除"; } }
        protected override Guid CanonicalName { get { return new Guid("124AC498-75CF-5595-B46B-2CEFD81211A4"); } }
        protected override int Flags { get { return Native.ECF_DEFAULT; } }
        protected override string Action { get { return "Remove"; } }
        protected override string Scope { get { return "All"; } }
    }

    /// <summary>纯分隔符条目。</summary>
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

        /// <summary>分隔符不响应点击（override 而非 new，否则接口映射仍指向基类）。</summary>
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
        protected override string Title { get { return "打开 PATH 管理器"; } }
        protected override string ToolTip { get { return "查看 PATH、备份历史与变更日志"; } }
        protected override Guid CanonicalName { get { return new Guid("9921ED8D-5AAF-563A-BAF4-0276A003291B"); } }
        protected override int Flags { get { return Native.ECF_DEFAULT; } }
        protected override string Action { get { return "OpenManager"; } }
        protected override string Scope { get { return null; } }
    }

    #endregion

    #region 子命令枚举器

    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [Guid("53E97A7A-9ECB-5EC8-8499-CE6030C691BB")]
    public class SubCommandEnum : IEnumExplorerCommand
    {
        private int _index = 0;

        public SubCommandEnum()
        {
            Helper.Log("  SubCommandEnum 构造");
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
                       " 数组=" + (pUICommand == null ? "null" : pUICommand.Length.ToString()));
            try
            {
                if (pUICommand == null || pUICommand.Length < celt)
                {
                    Helper.Log("  Next -> E_INVALIDARG（数组长度不足）");
                    return Native.E_INVALIDARG;
                }

                IExplorerCommand[] all = Build();
                uint fetched = 0;
                while (fetched < celt && _index < all.Length)
                {
                    Helper.Log("  Next 产出 [" + _index + "] " + all[_index].GetType().Name);
                    pUICommand[fetched] = all[_index];
                    _index++;
                    fetched++;
                }

                pceltFetched = fetched;
                Helper.Log("  Next -> 取到 " + fetched + " 个, hr=" +
                           ((fetched == celt) ? "S_OK" : "S_FALSE"));
                return (fetched == celt) ? Native.S_OK : Native.S_FALSE;
            }
            catch (Exception ex)
            {
                Helper.Log("  Next 异常: " + ex.GetType().Name + " " + ex.Message);
                return Native.E_FAIL;
            }
        }

        public int Skip(uint celt)
        {
            try { _index += (int)celt; return Native.S_OK; }
            catch { return Native.E_FAIL; }
        }

        public void Reset()
        {
            Helper.Log("  SubCommandEnum.Reset");
            _index = 0;
        }

        public IEnumExplorerCommand Clone()
        {
            Helper.Log("  SubCommandEnum.Clone");
            return new SubCommandEnum();
        }
    }

    #endregion
}
