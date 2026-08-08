# FocusVeil Windows

FocusVeil Windows 是一款原生 Windows 托盘应用，用于在多窗口工作环境中突出当前视觉焦点。应用会跟随当前活动窗口，在保持该窗口原有亮度的同时压暗其他窗口和桌面背景，减少阅读、写作、开发和会议场景中的视觉干扰。

## 功能范围

- 自动跟随当前活动窗口，并在窗口关闭后让同一显示器上最靠前的可见窗口接管焦点。
- 支持多个显示器，每块屏幕独立保留最近活跃窗口。
- 支持背景压暗强度调节。
- 支持分级亮度，最近活跃的历史窗口会按顺序保留不同亮度。
- 支持历史高亮窗口数量设置，范围为一至四个历史窗口。
- 支持登录时启动。
- 支持从 GitHub Releases 检查新版本并打开发布页。
- 不截屏，不录屏，不保存窗口内容。

## 系统要求

- Windows 10 或更高版本。
- Visual Studio 2022 的桌面 C++ 开发工具。
- CMake。
- Inno Setup，用于生成面向用户分发的安装程序。

Windows 版通过当前用户会话中的窗口边界和层级信息绘制遮罩，不需要 macOS 版使用的辅助功能授权。管理员权限窗口和某些受保护界面可能受 Windows 完整性级别限制，遮罩层级可能无法完全覆盖这些窗口后的区域。

## 构建方式

在仓库根目录打开 PowerShell，运行：

```powershell
.\Windows\FocusVeil\Scripts\build.ps1
```

构建完成后会生成：

```text
outputs\windows\FocusVeil.exe
```

生成安装程序时运行：

```powershell
.\Windows\FocusVeil\Scripts\buildInstaller.ps1
```

安装程序生成后位于：

```text
outputs\windows\FocusVeilSetup.exe
```

面向普通用户分发时，发布页上传 `FocusVeilSetup.exe` 即可。用户下载后运行安装程序，完成安装后可以从开始菜单启动应用；安装过程可选择创建桌面快捷方式，也可选择随 Windows 启动。

也可以直接使用 CMake：

```powershell
cmake -S .\Windows\FocusVeil -B .\work\windows-build
cmake --build .\work\windows-build --config Release
```

## 使用方式

启动 `FocusVeil.exe` 后，应用会常驻 Windows 通知区域。点击托盘图标可以打开菜单，菜单中提供启用背景压暗、启用分级亮度、设置、登录时启动、检查更新、关于和退出。

设置窗口中可以调整背景压暗强度、历史高亮窗口数量以及各历史层级亮度。分级亮度关闭时，仅当前活动窗口保持原有亮度；分级亮度开启时，最近活跃的历史窗口会按层级保留部分亮度，其他区域应用最深压暗强度。

## 技术实现

Windows 版使用 Win32 桌面接口实现。应用通过前台窗口读取、顶层窗口枚举、DWM 扩展边界和多显示器枚举判断窗口位置与显示器归属。遮罩使用透明分层窗口绘制，并通过窗口顺序放置在目标窗口后方，从而让目标窗口保持原有显示效果。

登录启动状态保存到当前用户的运行项。用户设置保存到当前用户注册表中的 FocusVeil 配置项。检查更新会读取 GitHub Releases 最新版本信息，发现新版本后由用户选择是否打开发布页下载。

## 与 macOS 版的差异

macOS 版使用 Sparkle 完成应用内下载、校验、安装和重启。Windows 版当前提供版本检查和发布页入口，安装包、自更新和代码签名流程需要在 Windows 发布体系确定后继续补齐。

Windows 的窗口层级、管理员权限窗口、全屏独占程序和游戏模式与 macOS 不同。普通桌面窗口、多显示器办公场景和浏览器全屏场景是当前优先覆盖的使用范围。
