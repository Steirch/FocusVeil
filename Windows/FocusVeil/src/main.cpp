#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#define NOMINMAX

#include <windows.h>
#include <shellapi.h>
#include <dwmapi.h>
#include <commctrl.h>
#include <winhttp.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cwchar>
#include <cstdint>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr wchar_t kAppName[] = L"FocusVeil";
constexpr wchar_t kAppVersion[] = L"0.1.11";
constexpr wchar_t kRepositoryLatestReleaseUrl[] =
    L"https://github.com/Steirch/FocusVeil/releases/latest";
constexpr wchar_t kRegistryPath[] = L"Software\\FocusVeil";
constexpr wchar_t kRunRegistryPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kMessageWindowClass[] = L"FocusVeilMessageWindow";
constexpr wchar_t kOverlayWindowClass[] = L"FocusVeilOverlayWindow";
constexpr wchar_t kSettingsWindowClass[] = L"FocusVeilSettingsWindow";
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\FocusVeilWindows";

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT_PTR kRefreshTimer = 1;
constexpr UINT kRefreshIntervalMilliseconds = 100;

constexpr int kMenuToggleEnabled = 1001;
constexpr int kMenuToggleRankedBrightness = 1002;
constexpr int kMenuSettings = 1003;
constexpr int kMenuLaunchAtLogin = 1004;
constexpr int kMenuCheckUpdates = 1005;
constexpr int kMenuAbout = 1006;
constexpr int kMenuQuit = 1007;

constexpr int kDimmingTrack = 2001;
constexpr int kDimmingValue = 2002;
constexpr int kRankedBrightnessCheck = 2003;
constexpr int kHighlightCountTrack = 2004;
constexpr int kHighlightCountValue = 2005;
constexpr int kRankedBrightnessTrackBase = 2100;
constexpr int kRankedBrightnessValueBase = 2200;
constexpr int kResetRankedBrightness = 2300;

constexpr double kDefaultDimmingAmount = 0.52;
constexpr int kMinimumDimmingPercent = 8;
constexpr int kMaximumDimmingPercent = 82;
constexpr int kMinimumHighlightWindowCount = 1;
constexpr int kMaximumHighlightWindowCount = 4;
constexpr int kMinimumRankedBrightnessPercent = 0;
constexpr int kMaximumRankedBrightnessPercent = 95;
constexpr double kMinimumRankedBrightness = 0.0;
constexpr double kMaximumRankedBrightness = 0.95;
constexpr double kSingleRankedBrightnessDefault = 0.55;
constexpr double kTopRankedBrightnessDefault = 0.62;
constexpr double kBottomRankedBrightnessDefault = 0.06;
constexpr double kRankedBrightnessDefaultCurve = 1.35;
constexpr double kRankedBrightnessResponseCurve = 1.45;
constexpr double kMinimumVisibleWindowAreaRatio = 0.08;

struct MonitorSnapshot {
    HMONITOR handle = nullptr;
    RECT bounds{};
};

struct WindowSnapshot {
    HWND hwnd = nullptr;
    DWORD processIdentifier = 0;
    RECT frame{};
    HMONITOR monitor = nullptr;
    bool fullScreen = false;
};

using MonitorKey = std::uintptr_t;

MonitorKey MonitorKeyForHandle(HMONITOR monitor) {
    return reinterpret_cast<MonitorKey>(monitor);
}

int ClampInt(int value, int minimum, int maximum) {
    return std::min(std::max(value, minimum), maximum);
}

double ClampDouble(double value, double minimum, double maximum) {
    return std::min(std::max(value, minimum), maximum);
}

int PercentFromAmount(double amount) {
    return ClampInt(
        static_cast<int>(std::lround(amount * 100.0)),
        kMinimumDimmingPercent,
        kMaximumDimmingPercent
    );
}

double AmountFromPercent(int percent) {
    return ClampDouble(
        static_cast<double>(percent) / 100.0,
        static_cast<double>(kMinimumDimmingPercent) / 100.0,
        static_cast<double>(kMaximumDimmingPercent) / 100.0
    );
}

int PercentFromBrightness(double brightness) {
    return ClampInt(
        static_cast<int>(std::lround(brightness * 100.0)),
        kMinimumRankedBrightnessPercent,
        kMaximumRankedBrightnessPercent
    );
}

double BrightnessFromPercent(int percent) {
    return ClampDouble(
        static_cast<double>(percent) / 100.0,
        kMinimumRankedBrightness,
        kMaximumRankedBrightness
    );
}

std::wstring PercentText(int percent) {
    return std::to_wstring(percent) + L"%";
}

LONG RectWidth(const RECT& rect) {
    return rect.right - rect.left;
}

LONG RectHeight(const RECT& rect) {
    return rect.bottom - rect.top;
}

double RectArea(const RECT& rect) {
    LONG width = RectWidth(rect);
    LONG height = RectHeight(rect);
    if (width <= 0 || height <= 0) {
        return 0.0;
    }
    return static_cast<double>(width) * static_cast<double>(height);
}

RECT RectIntersectionValue(const RECT& first, const RECT& second) {
    RECT intersection{};
    if (!IntersectRect(&intersection, &first, &second)) {
        return RECT{};
    }
    return intersection;
}

double RectIntersectionArea(const RECT& first, const RECT& second) {
    return RectArea(RectIntersectionValue(first, second));
}

bool IsSubstantialFrame(const RECT& rect) {
    return RectWidth(rect) > 40 && RectHeight(rect) > 40;
}

double EffectiveRankedBrightness(double brightness) {
    brightness = ClampDouble(
        brightness,
        kMinimumRankedBrightness,
        kMaximumRankedBrightness
    );
    return std::pow(brightness, kRankedBrightnessResponseCurve);
}

double DefaultRankedBrightnessForLevel(int level, int configuredCount) {
    level = ClampInt(
        level,
        kMinimumHighlightWindowCount,
        kMaximumHighlightWindowCount
    );
    configuredCount = ClampInt(
        std::max(configuredCount, level),
        kMinimumHighlightWindowCount,
        kMaximumHighlightWindowCount
    );

    if (configuredCount <= kMinimumHighlightWindowCount) {
        return kSingleRankedBrightnessDefault;
    }

    double position = static_cast<double>(configuredCount - level) /
        static_cast<double>(
            configuredCount - kMinimumHighlightWindowCount
        );
    double brightness = kBottomRankedBrightnessDefault +
        (kTopRankedBrightnessDefault - kBottomRankedBrightnessDefault) *
            std::pow(position, kRankedBrightnessDefaultCurve);
    return ClampDouble(
        brightness,
        kMinimumRankedBrightness,
        kMaximumRankedBrightness
    );
}

double IncrementalDimmingAmount(double previousAmount, double targetAmount) {
    previousAmount = ClampDouble(previousAmount, 0.0, 0.95);
    targetAmount = ClampDouble(targetAmount, previousAmount, 0.95);
    if (targetAmount <= previousAmount) {
        return 0.0;
    }
    return (targetAmount - previousAmount) / (1.0 - previousAmount);
}

BYTE AlphaForDimmingAmount(double amount) {
    amount = ClampDouble(amount, 0.0, 0.95);
    return static_cast<BYTE>(std::lround(amount * 255.0));
}

BOOL CALLBACK EnumerateMonitorsCallback(
    HMONITOR monitor,
    HDC,
    LPRECT bounds,
    LPARAM context
) {
    auto* monitors = reinterpret_cast<std::vector<MonitorSnapshot>*>(context);
    monitors->push_back(MonitorSnapshot{monitor, *bounds});
    return TRUE;
}

std::vector<MonitorSnapshot> EnumerateMonitorSnapshots() {
    std::vector<MonitorSnapshot> monitors;
    EnumDisplayMonitors(
        nullptr,
        nullptr,
        EnumerateMonitorsCallback,
        reinterpret_cast<LPARAM>(&monitors)
    );
    return monitors;
}

HMONITOR MonitorWithLargestIntersection(
    const RECT& frame,
    const std::vector<MonitorSnapshot>& monitors
) {
    double largestArea = 0.0;
    HMONITOR selectedMonitor = nullptr;
    for (const auto& monitor : monitors) {
        double area = RectIntersectionArea(frame, monitor.bounds);
        if (area > largestArea) {
            largestArea = area;
            selectedMonitor = monitor.handle;
        }
    }
    return selectedMonitor;
}

const RECT* BoundsForMonitor(
    HMONITOR monitor,
    const std::vector<MonitorSnapshot>& monitors
) {
    for (const auto& snapshot : monitors) {
        if (snapshot.handle == monitor) {
            return &snapshot.bounds;
        }
    }
    return nullptr;
}

bool WindowFrameIsSubstantiallyVisible(
    const RECT& frame,
    const std::vector<MonitorSnapshot>& monitors
) {
    double frameArea = RectArea(frame);
    if (frameArea <= 0.0) {
        return false;
    }
    if (monitors.empty()) {
        return true;
    }

    double visibleArea = 0.0;
    for (const auto& monitor : monitors) {
        visibleArea += RectIntersectionArea(frame, monitor.bounds);
    }
    return visibleArea / frameArea >= kMinimumVisibleWindowAreaRatio;
}

bool WindowFrameCoversDisplay(
    const RECT& frame,
    HMONITOR monitor,
    const std::vector<MonitorSnapshot>& monitors
) {
    const RECT* displayBounds = BoundsForMonitor(monitor, monitors);
    if (displayBounds == nullptr || RectArea(frame) <= 0.0) {
        return false;
    }

    double displayArea = RectArea(*displayBounds);
    if (displayArea <= 0.0) {
        return false;
    }

    double coveredDisplayArea = RectIntersectionArea(frame, *displayBounds);
    double coverageRatio = coveredDisplayArea / displayArea;
    LONG edgeTolerance = 36;

    return coverageRatio >= 0.95 &&
        frame.left <= displayBounds->left + edgeTolerance &&
        frame.top <= displayBounds->top + edgeTolerance &&
        frame.right >= displayBounds->right - edgeTolerance &&
        frame.bottom >= displayBounds->bottom - edgeTolerance;
}

bool WindowFrameLikelyFillsDisplay(
    const RECT& frame,
    HMONITOR monitor,
    const std::vector<MonitorSnapshot>& monitors
) {
    const RECT* displayBounds = BoundsForMonitor(monitor, monitors);
    if (displayBounds == nullptr || RectArea(frame) <= 0.0) {
        return false;
    }

    double displayArea = RectArea(*displayBounds);
    if (displayArea <= 0.0) {
        return false;
    }

    RECT intersection = RectIntersectionValue(frame, *displayBounds);
    double coverageRatio = RectArea(intersection) / displayArea;
    double widthRatio = static_cast<double>(RectWidth(intersection)) /
        static_cast<double>(RectWidth(*displayBounds));
    double heightRatio = static_cast<double>(RectHeight(intersection)) /
        static_cast<double>(RectHeight(*displayBounds));
    LONG edgeTolerance = 64;

    bool spansDisplayWidth =
        widthRatio >= 0.96 &&
        frame.left <= displayBounds->left + edgeTolerance &&
        frame.right >= displayBounds->right - edgeTolerance;
    bool touchesVerticalDisplayEdge =
        frame.top <= displayBounds->top + edgeTolerance ||
        frame.bottom >= displayBounds->bottom - edgeTolerance;

    return coverageRatio >= 0.88 &&
        heightRatio >= 0.86 &&
        spansDisplayWidth &&
        touchesVerticalDisplayEdge;
}

bool TryGetWindowFrame(HWND hwnd, RECT* frame) {
    RECT bounds{};
    HRESULT result = DwmGetWindowAttribute(
        hwnd,
        DWMWA_EXTENDED_FRAME_BOUNDS,
        &bounds,
        sizeof(bounds)
    );
    if (FAILED(result) || !IsSubstantialFrame(bounds)) {
        if (!GetWindowRect(hwnd, &bounds)) {
            return false;
        }
    }

    if (!IsSubstantialFrame(bounds)) {
        return false;
    }

    *frame = bounds;
    return true;
}

bool IsWindowCloaked(HWND hwnd) {
    BOOL cloaked = FALSE;
    HRESULT result = DwmGetWindowAttribute(
        hwnd,
        DWMWA_CLOAKED,
        &cloaked,
        sizeof(cloaked)
    );
    return SUCCEEDED(result) && cloaked;
}

std::wstring ClassNameForWindow(HWND hwnd) {
    wchar_t buffer[256]{};
    int length = GetClassNameW(
        hwnd,
        buffer,
        static_cast<int>(sizeof(buffer) / sizeof(buffer[0]))
    );
    if (length <= 0) {
        return L"";
    }
    return std::wstring(buffer, static_cast<std::size_t>(length));
}

bool IsExcludedShellClass(const std::wstring& className) {
    static const wchar_t* excludedClasses[] = {
        L"ApplicationManager_DesktopShellWindow",
        L"Button",
        L"DV2ControlHost",
        L"NotifyIconOverflowWindow",
        L"Progman",
        L"Shell_SecondaryTrayWnd",
        L"Shell_TrayWnd",
        L"Windows.UI.Core.CoreWindow",
        L"WorkerW"
    };

    for (const wchar_t* excludedClass : excludedClasses) {
        if (className == excludedClass) {
            return true;
        }
    }
    return false;
}

bool IsCandidateWindow(
    HWND hwnd,
    DWORD ownProcessIdentifier,
    const std::vector<MonitorSnapshot>& monitors
) {
    if (hwnd == nullptr || !IsWindow(hwnd) || !IsWindowVisible(hwnd)) {
        return false;
    }
    if (IsIconic(hwnd)) {
        return false;
    }

    HWND root = GetAncestor(hwnd, GA_ROOT);
    if (root != hwnd) {
        return false;
    }

    DWORD processIdentifier = 0;
    GetWindowThreadProcessId(hwnd, &processIdentifier);
    if (processIdentifier == 0 || processIdentifier == ownProcessIdentifier) {
        return false;
    }

    if (IsWindowCloaked(hwnd)) {
        return false;
    }

    std::wstring className = ClassNameForWindow(hwnd);
    if (IsExcludedShellClass(className)) {
        return false;
    }

    LONG_PTR exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (
        (exStyle & WS_EX_TOOLWINDOW) != 0 &&
        (exStyle & WS_EX_APPWINDOW) == 0
    ) {
        return false;
    }

    HWND owner = GetWindow(hwnd, GW_OWNER);
    if (owner != nullptr && (exStyle & WS_EX_APPWINDOW) == 0) {
        return false;
    }

    RECT frame{};
    if (!TryGetWindowFrame(hwnd, &frame)) {
        return false;
    }

    if (!WindowFrameIsSubstantiallyVisible(frame, monitors)) {
        return false;
    }

    if ((exStyle & WS_EX_LAYERED) != 0) {
        COLORREF colorKey = 0;
        BYTE alpha = 255;
        DWORD flags = 0;
        if (
            GetLayeredWindowAttributes(hwnd, &colorKey, &alpha, &flags) &&
            (flags & LWA_ALPHA) != 0 &&
            alpha == 0
        ) {
            return false;
        }
    }

    return true;
}

bool SnapshotForWindow(
    HWND hwnd,
    DWORD ownProcessIdentifier,
    const std::vector<MonitorSnapshot>& monitors,
    WindowSnapshot* snapshot
) {
    hwnd = GetAncestor(hwnd, GA_ROOT);
    if (!IsCandidateWindow(hwnd, ownProcessIdentifier, monitors)) {
        return false;
    }

    RECT frame{};
    if (!TryGetWindowFrame(hwnd, &frame)) {
        return false;
    }

    HMONITOR monitor = MonitorWithLargestIntersection(frame, monitors);
    if (monitor == nullptr) {
        return false;
    }

    DWORD processIdentifier = 0;
    GetWindowThreadProcessId(hwnd, &processIdentifier);
    bool fullScreen =
        WindowFrameCoversDisplay(frame, monitor, monitors) ||
        WindowFrameLikelyFillsDisplay(frame, monitor, monitors);

    *snapshot = WindowSnapshot{
        hwnd,
        processIdentifier,
        frame,
        monitor,
        fullScreen
    };
    return true;
}

struct EnumerateWindowsContext {
    DWORD ownProcessIdentifier = 0;
    const std::vector<MonitorSnapshot>* monitors = nullptr;
    std::vector<WindowSnapshot>* snapshots = nullptr;
};

BOOL CALLBACK EnumerateWindowsCallback(HWND hwnd, LPARAM contextPointer) {
    auto* context = reinterpret_cast<EnumerateWindowsContext*>(contextPointer);
    WindowSnapshot snapshot{};
    if (
        SnapshotForWindow(
            hwnd,
            context->ownProcessIdentifier,
            *context->monitors,
            &snapshot
        )
    ) {
        context->snapshots->push_back(snapshot);
    }
    return TRUE;
}

std::vector<WindowSnapshot> VisibleWindowSnapshotsExcludingProcess(
    DWORD ownProcessIdentifier,
    const std::vector<MonitorSnapshot>& monitors
) {
    std::vector<WindowSnapshot> snapshots;
    EnumerateWindowsContext context{
        ownProcessIdentifier,
        &monitors,
        &snapshots
    };
    EnumWindows(EnumerateWindowsCallback, reinterpret_cast<LPARAM>(&context));
    return snapshots;
}

DWORD ReadRegistryDword(
    const wchar_t* valueName,
    DWORD defaultValue,
    DWORD minimumValue,
    DWORD maximumValue
) {
    DWORD value = 0;
    DWORD size = sizeof(value);
    LSTATUS status = RegGetValueW(
        HKEY_CURRENT_USER,
        kRegistryPath,
        valueName,
        RRF_RT_REG_DWORD,
        nullptr,
        &value,
        &size
    );
    if (status != ERROR_SUCCESS) {
        return defaultValue;
    }
    return std::min(std::max(value, minimumValue), maximumValue);
}

void WriteRegistryDword(const wchar_t* valueName, DWORD value) {
    HKEY key = nullptr;
    LSTATUS status = RegCreateKeyExW(
        HKEY_CURRENT_USER,
        kRegistryPath,
        0,
        nullptr,
        REG_OPTION_NON_VOLATILE,
        KEY_SET_VALUE,
        nullptr,
        &key,
        nullptr
    );
    if (status != ERROR_SUCCESS) {
        return;
    }

    RegSetValueExW(
        key,
        valueName,
        0,
        REG_DWORD,
        reinterpret_cast<const BYTE*>(&value),
        sizeof(value)
    );
    RegCloseKey(key);
}

void DeleteRegistryValue(const wchar_t* valueName) {
    HKEY key = nullptr;
    if (
        RegOpenKeyExW(
            HKEY_CURRENT_USER,
            kRegistryPath,
            0,
            KEY_SET_VALUE,
            &key
        ) == ERROR_SUCCESS
    ) {
        RegDeleteValueW(key, valueName);
        RegCloseKey(key);
    }
}

std::wstring RankedBrightnessValueName(int level) {
    return L"RankedBrightnessLevel" + std::to_wstring(level) + L"Percent";
}

class Settings {
public:
    bool enabled = true;
    double dimmingAmount = kDefaultDimmingAmount;
    bool rankedBrightnessEnabled = false;
    int highlightWindowCount = 2;
    bool rankedBrightnessCustomized = false;
    double rankedBrightness[kMaximumHighlightWindowCount + 1]{};

    void Load() {
        enabled = ReadRegistryDword(L"Enabled", 1, 0, 1) != 0;
        dimmingAmount = AmountFromPercent(static_cast<int>(
            ReadRegistryDword(
                L"DimmingAmountPercent",
                PercentFromAmount(kDefaultDimmingAmount),
                kMinimumDimmingPercent,
                kMaximumDimmingPercent
            )
        ));
        rankedBrightnessEnabled =
            ReadRegistryDword(L"RankedBrightnessEnabled", 0, 0, 1) != 0;
        highlightWindowCount = static_cast<int>(
            ReadRegistryDword(
                L"HighlightWindowCount",
                2,
                kMinimumHighlightWindowCount,
                kMaximumHighlightWindowCount
            )
        );
        rankedBrightnessCustomized =
            ReadRegistryDword(L"RankedBrightnessCustomized", 0, 0, 1) != 0;

        for (
            int level = kMinimumHighlightWindowCount;
            level <= kMaximumHighlightWindowCount;
            ++level
        ) {
            int defaultPercent = PercentFromBrightness(
                DefaultRankedBrightnessForLevel(level, highlightWindowCount)
            );
            std::wstring valueName = RankedBrightnessValueName(level);
            rankedBrightness[level] = BrightnessFromPercent(static_cast<int>(
                ReadRegistryDword(
                    valueName.c_str(),
                    static_cast<DWORD>(defaultPercent),
                    kMinimumRankedBrightnessPercent,
                    kMaximumRankedBrightnessPercent
                )
            ));
        }
        NormalizeRankedBrightnessValues();
    }

    void SaveAll() const {
        WriteRegistryDword(L"Enabled", enabled ? 1 : 0);
        WriteRegistryDword(
            L"DimmingAmountPercent",
            static_cast<DWORD>(PercentFromAmount(dimmingAmount))
        );
        WriteRegistryDword(
            L"RankedBrightnessEnabled",
            rankedBrightnessEnabled ? 1 : 0
        );
        WriteRegistryDword(
            L"HighlightWindowCount",
            static_cast<DWORD>(highlightWindowCount)
        );
        WriteRegistryDword(
            L"RankedBrightnessCustomized",
            rankedBrightnessCustomized ? 1 : 0
        );
        for (
            int level = kMinimumHighlightWindowCount;
            level <= kMaximumHighlightWindowCount;
            ++level
        ) {
            std::wstring valueName = RankedBrightnessValueName(level);
            WriteRegistryDword(
                valueName.c_str(),
                static_cast<DWORD>(PercentFromBrightness(rankedBrightness[level]))
            );
        }
    }

    double RankedBrightnessForLevel(int level) const {
        if (!rankedBrightnessCustomized) {
            return DefaultRankedBrightnessForLevel(level, highlightWindowCount);
        }
        level = ClampInt(
            level,
            kMinimumHighlightWindowCount,
            kMaximumHighlightWindowCount
        );
        return ClampDouble(
            rankedBrightness[level],
            kMinimumRankedBrightness,
            kMaximumRankedBrightness
        );
    }

    void SetRankedBrightnessForLevel(int level, double brightness) {
        EnsureRankedBrightnessCustomization();
        level = ClampInt(
            level,
            kMinimumHighlightWindowCount,
            kMaximumHighlightWindowCount
        );
        rankedBrightness[level] = ClampDouble(
            brightness,
            kMinimumRankedBrightness,
            kMaximumRankedBrightness
        );
        NormalizeRankedBrightnessValues();
        SaveAll();
    }

    void ResetRankedBrightnessLevels() {
        for (
            int level = kMinimumHighlightWindowCount;
            level <= kMaximumHighlightWindowCount;
            ++level
        ) {
            rankedBrightness[level] =
                DefaultRankedBrightnessForLevel(level, highlightWindowCount);
            std::wstring valueName = RankedBrightnessValueName(level);
            DeleteRegistryValue(valueName.c_str());
        }
        rankedBrightnessCustomized = false;
        WriteRegistryDword(L"RankedBrightnessCustomized", 0);
    }

    void NormalizeRankedBrightnessValues() {
        double previousBrightness = kMaximumRankedBrightness;
        for (
            int level = kMinimumHighlightWindowCount;
            level <= kMaximumHighlightWindowCount;
            ++level
        ) {
            double brightness = rankedBrightness[level];
            brightness = std::min(brightness, previousBrightness);
            rankedBrightness[level] = ClampDouble(
                brightness,
                kMinimumRankedBrightness,
                kMaximumRankedBrightness
            );
            previousBrightness = rankedBrightness[level];
        }
    }

private:
    void EnsureRankedBrightnessCustomization() {
        if (rankedBrightnessCustomized) {
            return;
        }
        for (
            int level = kMinimumHighlightWindowCount;
            level <= kMaximumHighlightWindowCount;
            ++level
        ) {
            rankedBrightness[level] =
                DefaultRankedBrightnessForLevel(level, highlightWindowCount);
        }
        rankedBrightnessCustomized = true;
    }
};

class FocusController {
public:
    Settings settings;

    void Initialize(HINSTANCE instance) {
        instance_ = instance;
        ownProcessIdentifier_ = GetCurrentProcessId();
        settings.Load();
        RebuildOverlays();
    }

    void Shutdown() {
        HideAllOverlayLayers();
        for (auto& layer : overlayLayers_) {
            for (HWND overlay : layer) {
                if (IsWindow(overlay)) {
                    DestroyWindow(overlay);
                }
            }
        }
        overlayLayers_.clear();
        overlayDisplayIdentifiers_.clear();
        monitorSnapshots_.clear();
    }

    void SetEnabled(bool enabled) {
        settings.enabled = enabled;
        settings.SaveAll();
        Refresh();
    }

    void SetDimmingAmount(double amount) {
        settings.dimmingAmount = AmountFromPercent(PercentFromAmount(amount));
        settings.SaveAll();
        Refresh();
    }

    void SetRankedBrightnessEnabled(bool enabled) {
        settings.rankedBrightnessEnabled = enabled;
        settings.SaveAll();
        RebuildOverlays();
        Refresh();
    }

    void SetHighlightWindowCount(int count) {
        settings.highlightWindowCount = ClampInt(
            count,
            kMinimumHighlightWindowCount,
            kMaximumHighlightWindowCount
        );
        settings.SaveAll();
        RebuildOverlays();
        Refresh();
    }

    void SetRankedBrightnessForLevel(int level, double brightness) {
        settings.SetRankedBrightnessForLevel(level, brightness);
        Refresh();
    }

    void ResetRankedBrightnessLevels() {
        settings.ResetRankedBrightnessLevels();
        Refresh();
    }

    void RebuildOverlays() {
        HideAllOverlayLayers();
        for (auto& layer : overlayLayers_) {
            for (HWND overlay : layer) {
                if (IsWindow(overlay)) {
                    DestroyWindow(overlay);
                }
            }
        }
        overlayLayers_.clear();
        overlayDisplayIdentifiers_.clear();

        monitorSnapshots_ = EnumerateMonitorSnapshots();
        for (const auto& monitor : monitorSnapshots_) {
            overlayDisplayIdentifiers_.push_back(MonitorKeyForHandle(monitor.handle));
        }
        PruneHistoriesForActiveDisplays();

        std::size_t layerCount = settings.rankedBrightnessEnabled
            ? static_cast<std::size_t>(settings.highlightWindowCount + 1)
            : 1;
        for (std::size_t layerIndex = 0; layerIndex < layerCount; ++layerIndex) {
            std::vector<HWND> overlays;
            for (const auto& monitor : monitorSnapshots_) {
                overlays.push_back(CreateOverlayWindow(monitor.bounds));
            }
            overlayLayers_.push_back(overlays);
        }
    }

    void Refresh() {
        if (!settings.enabled) {
            HideAllOverlayLayers();
            return;
        }

        HWND foregroundWindow = GetForegroundWindow();
        WindowSnapshot foregroundSnapshot{};
        bool foregroundHasWindow = SnapshotForWindow(
            foregroundWindow,
            ownProcessIdentifier_,
            monitorSnapshots_,
            &foregroundSnapshot
        );

        if (foregroundHasWindow) {
            RecordActiveWindowSnapshot(foregroundSnapshot);
        }

        std::vector<WindowSnapshot> visibleSnapshots =
            VisibleWindowSnapshotsExcludingProcess(
                ownProcessIdentifier_,
                monitorSnapshots_
            );
        std::map<HWND, WindowSnapshot> visibleSnapshotsByWindow;
        for (const WindowSnapshot& snapshot : visibleSnapshots) {
            visibleSnapshotsByWindow[snapshot.hwnd] = snapshot;
        }

        PruneKnownFullScreenWindows(visibleSnapshotsByWindow);

        if (foregroundHasWindow) {
            visibleSnapshotsByWindow[foregroundSnapshot.hwnd] = foregroundSnapshot;
            if (foregroundSnapshot.fullScreen) {
                knownFullScreenWindows_.insert(foregroundSnapshot.hwnd);
            } else {
                knownFullScreenWindows_.erase(foregroundSnapshot.hwnd);
            }
        } else {
            PromoteTopVisibleWindowSnapshotsForActiveDisplays(visibleSnapshots);
        }

        PruneRecentWindowNumbers(visibleSnapshotsByWindow);
        SeedMissingDisplayHistoriesWithVisibleWindowSnapshots(visibleSnapshots);

        if (!HasRecentWindowNumbersForActiveDisplays()) {
            HideAllOverlayLayers();
            return;
        }

        ApplyOverlayLayers(visibleSnapshotsByWindow);
    }

private:
    HINSTANCE instance_ = nullptr;
    DWORD ownProcessIdentifier_ = 0;
    std::vector<MonitorSnapshot> monitorSnapshots_;
    std::vector<MonitorKey> overlayDisplayIdentifiers_;
    std::vector<std::vector<HWND>> overlayLayers_;
    std::map<MonitorKey, std::vector<HWND>> recentWindowNumbersByDisplay_;
    std::set<HWND> knownFullScreenWindows_;

    HWND CreateOverlayWindow(const RECT& bounds) {
        HWND hwnd = CreateWindowExW(
            WS_EX_LAYERED |
                WS_EX_TRANSPARENT |
                WS_EX_TOOLWINDOW |
                WS_EX_NOACTIVATE,
            kOverlayWindowClass,
            L"",
            WS_POPUP,
            bounds.left,
            bounds.top,
            RectWidth(bounds),
            RectHeight(bounds),
            nullptr,
            nullptr,
            instance_,
            nullptr
        );
        if (hwnd != nullptr) {
            SetLayeredWindowAttributes(hwnd, RGB(0, 0, 0), 0, LWA_ALPHA);
        }
        return hwnd;
    }

    void HideOverlay(HWND overlay) {
        if (overlay != nullptr && IsWindowVisible(overlay)) {
            ShowWindow(overlay, SW_HIDE);
        }
    }

    void ShowOverlayBelowWindow(
        HWND overlay,
        HWND targetWindow,
        const RECT& bounds,
        double dimmingAmount
    ) {
        if (overlay == nullptr || targetWindow == nullptr || !IsWindow(targetWindow)) {
            HideOverlay(overlay);
            return;
        }

        SetLayeredWindowAttributes(
            overlay,
            RGB(0, 0, 0),
            AlphaForDimmingAmount(dimmingAmount),
            LWA_ALPHA
        );
        SetWindowPos(
            overlay,
            targetWindow,
            bounds.left,
            bounds.top,
            RectWidth(bounds),
            RectHeight(bounds),
            SWP_NOACTIVATE | SWP_SHOWWINDOW
        );
    }

    void HideAllOverlayLayers() {
        for (const auto& layer : overlayLayers_) {
            for (HWND overlay : layer) {
                HideOverlay(overlay);
            }
        }
    }

    void RecordActiveWindowSnapshot(const WindowSnapshot& snapshot) {
        if (snapshot.monitor == nullptr) {
            return;
        }
        MonitorKey monitorKey = MonitorKeyForHandle(snapshot.monitor);
        RemoveWindowFromAllDisplayHistories(snapshot.hwnd);

        auto& recentWindowNumbers =
            recentWindowNumbersByDisplay_[monitorKey];
        recentWindowNumbers.insert(recentWindowNumbers.begin(), snapshot.hwnd);
        TrimRecentWindowNumbers(recentWindowNumbers);
    }

    void RemoveWindowFromAllDisplayHistories(HWND hwnd) {
        for (auto& entry : recentWindowNumbersByDisplay_) {
            auto& recentWindowNumbers = entry.second;
            recentWindowNumbers.erase(
                std::remove(
                    recentWindowNumbers.begin(),
                    recentWindowNumbers.end(),
                    hwnd
                ),
                recentWindowNumbers.end()
            );
        }
    }

    void PruneKnownFullScreenWindows(
        const std::map<HWND, WindowSnapshot>& visibleSnapshotsByWindow
    ) {
        for (auto iterator = knownFullScreenWindows_.begin();
             iterator != knownFullScreenWindows_.end();) {
            if (visibleSnapshotsByWindow.find(*iterator) == visibleSnapshotsByWindow.end()) {
                iterator = knownFullScreenWindows_.erase(iterator);
            } else {
                ++iterator;
            }
        }
    }

    void PruneRecentWindowNumbers(
        const std::map<HWND, WindowSnapshot>& visibleSnapshotsByWindow
    ) {
        std::set<MonitorKey> activeDisplays(
            overlayDisplayIdentifiers_.begin(),
            overlayDisplayIdentifiers_.end()
        );

        for (auto iterator = recentWindowNumbersByDisplay_.begin();
             iterator != recentWindowNumbersByDisplay_.end();) {
            MonitorKey displayKey = iterator->first;
            auto& recentWindowNumbers = iterator->second;
            if (activeDisplays.find(displayKey) == activeDisplays.end()) {
                iterator = recentWindowNumbersByDisplay_.erase(iterator);
                continue;
            }

            recentWindowNumbers.erase(
                std::remove_if(
                    recentWindowNumbers.begin(),
                    recentWindowNumbers.end(),
                    [&](HWND hwnd) {
                        auto snapshotIterator =
                            visibleSnapshotsByWindow.find(hwnd);
                        if (snapshotIterator == visibleSnapshotsByWindow.end()) {
                            return true;
                        }
                        return MonitorKeyForHandle(snapshotIterator->second.monitor) !=
                            displayKey;
                    }
                ),
                recentWindowNumbers.end()
            );
            TrimRecentWindowNumbers(recentWindowNumbers);

            if (recentWindowNumbers.empty()) {
                iterator = recentWindowNumbersByDisplay_.erase(iterator);
            } else {
                ++iterator;
            }
        }
    }

    void SeedMissingDisplayHistoriesWithVisibleWindowSnapshots(
        const std::vector<WindowSnapshot>& visibleSnapshots
    ) {
        std::set<MonitorKey> activeDisplays(
            overlayDisplayIdentifiers_.begin(),
            overlayDisplayIdentifiers_.end()
        );

        for (const WindowSnapshot& snapshot : visibleSnapshots) {
            MonitorKey displayKey = MonitorKeyForHandle(snapshot.monitor);
            if (activeDisplays.find(displayKey) == activeDisplays.end()) {
                continue;
            }

            auto iterator = recentWindowNumbersByDisplay_.find(displayKey);
            if (iterator != recentWindowNumbersByDisplay_.end() &&
                !iterator->second.empty()) {
                continue;
            }

            auto& recentWindowNumbers =
                recentWindowNumbersByDisplay_[displayKey];
            recentWindowNumbers.push_back(snapshot.hwnd);
        }
    }

    void PromoteTopVisibleWindowSnapshotsForActiveDisplays(
        const std::vector<WindowSnapshot>& visibleSnapshots
    ) {
        std::set<MonitorKey> activeDisplays(
            overlayDisplayIdentifiers_.begin(),
            overlayDisplayIdentifiers_.end()
        );
        std::set<MonitorKey> promotedDisplays;

        for (const WindowSnapshot& snapshot : visibleSnapshots) {
            MonitorKey displayKey = MonitorKeyForHandle(snapshot.monitor);
            if (
                activeDisplays.find(displayKey) == activeDisplays.end() ||
                promotedDisplays.find(displayKey) != promotedDisplays.end()
            ) {
                continue;
            }

            RemoveWindowFromAllDisplayHistories(snapshot.hwnd);
            auto& recentWindowNumbers =
                recentWindowNumbersByDisplay_[displayKey];
            recentWindowNumbers.insert(recentWindowNumbers.begin(), snapshot.hwnd);
            TrimRecentWindowNumbers(recentWindowNumbers);
            promotedDisplays.insert(displayKey);

            if (promotedDisplays.size() == activeDisplays.size()) {
                return;
            }
        }
    }

    bool HasRecentWindowNumbersForActiveDisplays() const {
        for (MonitorKey displayKey : overlayDisplayIdentifiers_) {
            auto iterator = recentWindowNumbersByDisplay_.find(displayKey);
            if (iterator != recentWindowNumbersByDisplay_.end() &&
                !iterator->second.empty()) {
                return true;
            }
        }
        return false;
    }

    void TrimRecentWindowNumbers(std::vector<HWND>& recentWindowNumbers) {
        std::size_t limit =
            static_cast<std::size_t>(kMaximumHighlightWindowCount + 1);
        while (recentWindowNumbers.size() > limit) {
            recentWindowNumbers.pop_back();
        }
    }

    double TargetDimmingAmountForLayer(
        std::size_t layerIndex,
        std::size_t usedHighlightCount,
        double deepestAmount
    ) const {
        if (
            settings.rankedBrightnessEnabled &&
            usedHighlightCount > 0 &&
            layerIndex < usedHighlightCount
        ) {
            int level = static_cast<int>(layerIndex) + 1;
            double brightness = settings.RankedBrightnessForLevel(level);
            return deepestAmount * (1.0 - EffectiveRankedBrightness(brightness));
        }
        return deepestAmount;
    }

    void ApplyOverlayLayers(
        const std::map<HWND, WindowSnapshot>& visibleSnapshotsByWindow
    ) {
        int configuredHighlightCount = settings.rankedBrightnessEnabled
            ? settings.highlightWindowCount
            : 0;
        double deepestAmount = settings.dimmingAmount;

        for (std::size_t layerIndex = 0;
             layerIndex < overlayLayers_.size();
             ++layerIndex) {
            const auto& overlays = overlayLayers_[layerIndex];
            for (std::size_t overlayIndex = 0;
                 overlayIndex < overlays.size();
                 ++overlayIndex) {
                HWND overlay = overlays[overlayIndex];
                if (overlayIndex >= overlayDisplayIdentifiers_.size()) {
                    HideOverlay(overlay);
                    continue;
                }

                MonitorKey displayKey = overlayDisplayIdentifiers_[overlayIndex];
                auto recentIterator =
                    recentWindowNumbersByDisplay_.find(displayKey);
                if (
                    recentIterator == recentWindowNumbersByDisplay_.end() ||
                    recentIterator->second.empty()
                ) {
                    HideOverlay(overlay);
                    continue;
                }

                const auto& recentWindowNumbers = recentIterator->second;
                HWND topWindow = recentWindowNumbers.front();
                auto topSnapshotIterator = visibleSnapshotsByWindow.find(topWindow);
                if (topSnapshotIterator == visibleSnapshotsByWindow.end()) {
                    HideOverlay(overlay);
                    continue;
                }

                const WindowSnapshot& topSnapshot = topSnapshotIterator->second;
                if (
                    knownFullScreenWindows_.find(topWindow) !=
                        knownFullScreenWindows_.end() ||
                    WindowFrameCoversDisplay(
                        topSnapshot.frame,
                        topSnapshot.monitor,
                        monitorSnapshots_
                    ) ||
                    WindowFrameLikelyFillsDisplay(
                        topSnapshot.frame,
                        topSnapshot.monitor,
                        monitorSnapshots_
                    )
                ) {
                    HideOverlay(overlay);
                    continue;
                }

                std::size_t availableHighlightCount =
                    recentWindowNumbers.empty()
                        ? 0
                        : recentWindowNumbers.size() - 1;
                std::size_t usedHighlightCount = std::min(
                    static_cast<std::size_t>(configuredHighlightCount),
                    availableHighlightCount
                );
                std::size_t boundaryCount = usedHighlightCount + 1;
                if (layerIndex >= boundaryCount ||
                    layerIndex >= recentWindowNumbers.size()) {
                    HideOverlay(overlay);
                    continue;
                }

                double targetAmount = TargetDimmingAmountForLayer(
                    layerIndex,
                    usedHighlightCount,
                    deepestAmount
                );
                double previousTargetAmount = layerIndex == 0
                    ? 0.0
                    : TargetDimmingAmountForLayer(
                        layerIndex - 1,
                        usedHighlightCount,
                        deepestAmount
                    );
                double layerAmount = IncrementalDimmingAmount(
                    previousTargetAmount,
                    targetAmount
                );

                HWND targetWindow = recentWindowNumbers[layerIndex];
                ShowOverlayBelowWindow(
                    overlay,
                    targetWindow,
                    monitorSnapshots_[overlayIndex].bounds,
                    layerAmount
                );
            }
        }
    }

    void PruneHistoriesForActiveDisplays() {
        std::set<MonitorKey> activeDisplays(
            overlayDisplayIdentifiers_.begin(),
            overlayDisplayIdentifiers_.end()
        );
        for (auto iterator = recentWindowNumbersByDisplay_.begin();
             iterator != recentWindowNumbersByDisplay_.end();) {
            if (activeDisplays.find(iterator->first) == activeDisplays.end()) {
                iterator = recentWindowNumbersByDisplay_.erase(iterator);
            } else {
                ++iterator;
            }
        }
    }
};

LRESULT CALLBACK OverlayWindowProcedure(
    HWND hwnd,
    UINT message,
    WPARAM wParam,
    LPARAM lParam
) {
    switch (message) {
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    case WM_ERASEBKGND: {
        HDC dc = reinterpret_cast<HDC>(wParam);
        RECT bounds{};
        GetClientRect(hwnd, &bounds);
        HBRUSH brush = reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
        FillRect(dc, &bounds, brush);
        return 1;
    }
    case WM_PAINT: {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(hwnd, &paint);
        RECT bounds{};
        GetClientRect(hwnd, &bounds);
        HBRUSH brush = reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
        FillRect(dc, &bounds, brush);
        EndPaint(hwnd, &paint);
        return 0;
    }
    default:
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }
}

std::wstring GetExecutablePath() {
    std::wstring path(MAX_PATH, L'\0');
    DWORD length = GetModuleFileNameW(
        nullptr,
        path.data(),
        static_cast<DWORD>(path.size())
    );
    while (length == path.size()) {
        path.resize(path.size() * 2);
        length = GetModuleFileNameW(
            nullptr,
            path.data(),
            static_cast<DWORD>(path.size())
        );
    }
    path.resize(length);
    return path;
}

bool IsLaunchAtLoginEnabled() {
    wchar_t value[4096]{};
    DWORD size = sizeof(value);
    LSTATUS status = RegGetValueW(
        HKEY_CURRENT_USER,
        kRunRegistryPath,
        kAppName,
        RRF_RT_REG_SZ,
        nullptr,
        value,
        &size
    );
    return status == ERROR_SUCCESS && value[0] != L'\0';
}

bool SetLaunchAtLoginEnabled(bool enabled) {
    HKEY key = nullptr;
    LSTATUS status = RegCreateKeyExW(
        HKEY_CURRENT_USER,
        kRunRegistryPath,
        0,
        nullptr,
        REG_OPTION_NON_VOLATILE,
        KEY_SET_VALUE,
        nullptr,
        &key,
        nullptr
    );
    if (status != ERROR_SUCCESS) {
        return false;
    }

    bool success = true;
    if (enabled) {
        std::wstring command = L"\"" + GetExecutablePath() + L"\"";
        status = RegSetValueExW(
            key,
            kAppName,
            0,
            REG_SZ,
            reinterpret_cast<const BYTE*>(command.c_str()),
            static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t))
        );
        success = status == ERROR_SUCCESS;
    } else {
        status = RegDeleteValueW(key, kAppName);
        success = status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND;
    }

    RegCloseKey(key);
    return success;
}

std::wstring Utf8ToWide(const std::string& value) {
    if (value.empty()) {
        return L"";
    }
    int requiredLength = MultiByteToWideChar(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0
    );
    if (requiredLength <= 0) {
        return L"";
    }
    std::wstring result(static_cast<std::size_t>(requiredLength), L'\0');
    MultiByteToWideChar(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        result.data(),
        requiredLength
    );
    return result;
}

std::string ExtractJsonString(const std::string& json, const std::string& key) {
    std::string pattern = "\"" + key + "\"";
    std::size_t keyPosition = json.find(pattern);
    if (keyPosition == std::string::npos) {
        return "";
    }
    std::size_t colonPosition = json.find(':', keyPosition + pattern.size());
    if (colonPosition == std::string::npos) {
        return "";
    }
    std::size_t quotePosition = json.find('"', colonPosition + 1);
    if (quotePosition == std::string::npos) {
        return "";
    }

    std::string result;
    for (std::size_t index = quotePosition + 1; index < json.size(); ++index) {
        char character = json[index];
        if (character == '"') {
            return result;
        }
        if (character == '\\' && index + 1 < json.size()) {
            ++index;
            result.push_back(json[index]);
        } else {
            result.push_back(character);
        }
    }
    return "";
}

std::vector<int> ParseVersionParts(std::wstring version) {
    if (!version.empty() && (version[0] == L'v' || version[0] == L'V')) {
        version.erase(version.begin());
    }

    std::vector<int> parts;
    std::wstringstream stream(version);
    std::wstring segment;
    while (std::getline(stream, segment, L'.')) {
        try {
            parts.push_back(std::stoi(segment));
        } catch (...) {
            parts.push_back(0);
        }
    }
    return parts;
}

int CompareVersions(const std::wstring& left, const std::wstring& right) {
    std::vector<int> leftParts = ParseVersionParts(left);
    std::vector<int> rightParts = ParseVersionParts(right);
    std::size_t count = std::max(leftParts.size(), rightParts.size());
    leftParts.resize(count, 0);
    rightParts.resize(count, 0);

    for (std::size_t index = 0; index < count; ++index) {
        if (leftParts[index] < rightParts[index]) {
            return -1;
        }
        if (leftParts[index] > rightParts[index]) {
            return 1;
        }
    }
    return 0;
}

std::string ReadLatestReleaseJson() {
    HINTERNET session = WinHttpOpen(
        L"FocusVeil Windows",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0
    );
    if (session == nullptr) {
        return "";
    }
    WinHttpSetTimeouts(session, 3000, 3000, 3000, 5000);

    HINTERNET connection = WinHttpConnect(
        session,
        L"api.github.com",
        INTERNET_DEFAULT_HTTPS_PORT,
        0
    );
    if (connection == nullptr) {
        WinHttpCloseHandle(session);
        return "";
    }

    HINTERNET request = WinHttpOpenRequest(
        connection,
        L"GET",
        L"/repos/Steirch/FocusVeil/releases/latest",
        nullptr,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        WINHTTP_FLAG_SECURE
    );
    if (request == nullptr) {
        WinHttpCloseHandle(connection);
        WinHttpCloseHandle(session);
        return "";
    }

    const wchar_t headers[] =
        L"Accept: application/vnd.github+json\r\n"
        L"User-Agent: FocusVeil Windows\r\n";
    BOOL sent = WinHttpSendRequest(
        request,
        headers,
        static_cast<DWORD>(wcslen(headers)),
        WINHTTP_NO_REQUEST_DATA,
        0,
        0,
        0
    );
    if (!sent || !WinHttpReceiveResponse(request, nullptr)) {
        WinHttpCloseHandle(request);
        WinHttpCloseHandle(connection);
        WinHttpCloseHandle(session);
        return "";
    }

    std::string response;
    DWORD availableBytes = 0;
    while (
        WinHttpQueryDataAvailable(request, &availableBytes) &&
        availableBytes > 0
    ) {
        std::string buffer(availableBytes, '\0');
        DWORD readBytes = 0;
        if (
            !WinHttpReadData(
                request,
                buffer.data(),
                availableBytes,
                &readBytes
            )
        ) {
            break;
        }
        buffer.resize(readBytes);
        response += buffer;
    }

    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connection);
    WinHttpCloseHandle(session);
    return response;
}

void OpenUrl(const std::wstring& url) {
    ShellExecuteW(nullptr, L"open", url.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

class Application {
public:
    int Run(HINSTANCE instance, int showCommand) {
        (void)showCommand;
        instance_ = instance;

        INITCOMMONCONTROLSEX controls{};
        controls.dwSize = sizeof(controls);
        controls.dwICC = ICC_BAR_CLASSES | ICC_STANDARD_CLASSES;
        InitCommonControlsEx(&controls);

        if (!RegisterWindowClasses()) {
            return 1;
        }

        messageWindow_ = CreateWindowExW(
            0,
            kMessageWindowClass,
            kAppName,
            0,
            0,
            0,
            0,
            0,
            nullptr,
            nullptr,
            instance_,
            this
        );
        if (messageWindow_ == nullptr) {
            return 1;
        }

        focusController_.Initialize(instance_);
        AddTrayIcon();
        SetTimer(
            messageWindow_,
            kRefreshTimer,
            kRefreshIntervalMilliseconds,
            nullptr
        );
        focusController_.Refresh();

        MSG message{};
        while (GetMessageW(&message, nullptr, 0, 0) > 0) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }

        focusController_.Shutdown();
        if (updateThread_.joinable()) {
            updateThread_.join();
        }
        return static_cast<int>(message.wParam);
    }

    LRESULT HandleMessage(
        HWND hwnd,
        UINT message,
        WPARAM wParam,
        LPARAM lParam
    ) {
        switch (message) {
        case WM_TIMER:
            if (wParam == kRefreshTimer) {
                focusController_.Refresh();
                return 0;
            }
            break;
        case WM_COMMAND:
            HandleCommand(LOWORD(wParam));
            return 0;
        case WM_DISPLAYCHANGE:
        case WM_SETTINGCHANGE:
            focusController_.RebuildOverlays();
            focusController_.Refresh();
            return 0;
        case kTrayMessage:
            if (
                lParam == WM_RBUTTONUP ||
                lParam == WM_LBUTTONUP ||
                lParam == WM_CONTEXTMENU
            ) {
                ShowTrayMenu();
                return 0;
            }
            break;
        case WM_DESTROY:
            KillTimer(hwnd, kRefreshTimer);
            RemoveTrayIcon();
            PostQuitMessage(0);
            return 0;
        default:
            break;
        }

        return DefWindowProcW(hwnd, message, wParam, lParam);
    }

    LRESULT HandleSettingsMessage(
        HWND hwnd,
        UINT message,
        WPARAM wParam,
        LPARAM lParam
    ) {
        switch (message) {
        case WM_CREATE:
            CreateSettingsControls(hwnd);
            RefreshSettingsControls();
            return 0;
        case WM_HSCROLL:
            HandleSettingsTrackbar(reinterpret_cast<HWND>(lParam));
            return 0;
        case WM_COMMAND:
            HandleSettingsCommand(LOWORD(wParam));
            return 0;
        case WM_CLOSE:
            ShowWindow(hwnd, SW_HIDE);
            return 0;
        default:
            return DefWindowProcW(hwnd, message, wParam, lParam);
        }
    }

private:
    HINSTANCE instance_ = nullptr;
    HWND messageWindow_ = nullptr;
    HWND settingsWindow_ = nullptr;
    NOTIFYICONDATAW trayIcon_{};
    FocusController focusController_;
    std::atomic_bool updateCheckInProgress_{false};
    std::thread updateThread_;

    bool RegisterWindowClasses() {
        WNDCLASSEXW messageClass{};
        messageClass.cbSize = sizeof(messageClass);
        messageClass.lpfnWndProc = MessageWindowProcedure;
        messageClass.hInstance = instance_;
        messageClass.lpszClassName = kMessageWindowClass;
        if (!RegisterClassExW(&messageClass) &&
            GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return false;
        }

        WNDCLASSEXW overlayClass{};
        overlayClass.cbSize = sizeof(overlayClass);
        overlayClass.lpfnWndProc = OverlayWindowProcedure;
        overlayClass.hInstance = instance_;
        overlayClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        overlayClass.hbrBackground =
            reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
        overlayClass.lpszClassName = kOverlayWindowClass;
        if (!RegisterClassExW(&overlayClass) &&
            GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return false;
        }

        WNDCLASSEXW settingsClass{};
        settingsClass.cbSize = sizeof(settingsClass);
        settingsClass.lpfnWndProc = SettingsWindowProcedure;
        settingsClass.hInstance = instance_;
        settingsClass.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
        settingsClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        settingsClass.hbrBackground =
            reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        settingsClass.lpszClassName = kSettingsWindowClass;
        if (!RegisterClassExW(&settingsClass) &&
            GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return false;
        }

        return true;
    }

    static Application* ApplicationFromWindow(HWND hwnd) {
        return reinterpret_cast<Application*>(
            GetWindowLongPtrW(hwnd, GWLP_USERDATA)
        );
    }

    static LRESULT CALLBACK MessageWindowProcedure(
        HWND hwnd,
        UINT message,
        WPARAM wParam,
        LPARAM lParam
    ) {
        if (message == WM_NCCREATE) {
            auto* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
            auto* app = reinterpret_cast<Application*>(create->lpCreateParams);
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(app));
            return TRUE;
        }

        Application* app = ApplicationFromWindow(hwnd);
        if (app != nullptr) {
            return app->HandleMessage(hwnd, message, wParam, lParam);
        }
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }

    static LRESULT CALLBACK SettingsWindowProcedure(
        HWND hwnd,
        UINT message,
        WPARAM wParam,
        LPARAM lParam
    ) {
        if (message == WM_NCCREATE) {
            auto* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
            auto* app = reinterpret_cast<Application*>(create->lpCreateParams);
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(app));
            return TRUE;
        }

        Application* app = ApplicationFromWindow(hwnd);
        if (app != nullptr) {
            return app->HandleSettingsMessage(hwnd, message, wParam, lParam);
        }
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }

    void AddTrayIcon() {
        trayIcon_ = NOTIFYICONDATAW{};
        trayIcon_.cbSize = sizeof(trayIcon_);
        trayIcon_.hWnd = messageWindow_;
        trayIcon_.uID = 1;
        trayIcon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
        trayIcon_.uCallbackMessage = kTrayMessage;
        trayIcon_.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
        wcscpy_s(trayIcon_.szTip, kAppName);
        Shell_NotifyIconW(NIM_ADD, &trayIcon_);
        trayIcon_.uVersion = NOTIFYICON_VERSION_4;
        Shell_NotifyIconW(NIM_SETVERSION, &trayIcon_);
    }

    void RemoveTrayIcon() {
        if (trayIcon_.cbSize != 0) {
            Shell_NotifyIconW(NIM_DELETE, &trayIcon_);
            trayIcon_ = NOTIFYICONDATAW{};
        }
    }

    void ShowTrayMenu() {
        HMENU menu = CreatePopupMenu();
        if (menu == nullptr) {
            return;
        }

        AppendMenuW(
            menu,
            MF_STRING | (focusController_.settings.enabled ? MF_CHECKED : 0),
            kMenuToggleEnabled,
            L"启用背景压暗"
        );
        AppendMenuW(
            menu,
            MF_STRING |
                (focusController_.settings.rankedBrightnessEnabled
                    ? MF_CHECKED
                    : 0),
            kMenuToggleRankedBrightness,
            L"启用分级亮度"
        );
        AppendMenuW(menu, MF_STRING, kMenuSettings, L"设置...");
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(
            menu,
            MF_STRING | (IsLaunchAtLoginEnabled() ? MF_CHECKED : 0),
            kMenuLaunchAtLogin,
            L"登录时启动"
        );
        AppendMenuW(
            menu,
            MF_STRING |
                (updateCheckInProgress_.load() ? MF_GRAYED : 0),
            kMenuCheckUpdates,
            updateCheckInProgress_.load() ? L"正在检查更新" : L"检查更新"
        );
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, MF_STRING, kMenuAbout, L"关于 FocusVeil");
        AppendMenuW(menu, MF_STRING, kMenuQuit, L"退出 FocusVeil");

        POINT cursor{};
        GetCursorPos(&cursor);
        SetForegroundWindow(messageWindow_);
        TrackPopupMenu(
            menu,
            TPM_LEFTALIGN | TPM_BOTTOMALIGN | TPM_RIGHTBUTTON,
            cursor.x,
            cursor.y,
            0,
            messageWindow_,
            nullptr
        );
        PostMessageW(messageWindow_, WM_NULL, 0, 0);
        DestroyMenu(menu);
    }

    void HandleCommand(WORD command) {
        switch (command) {
        case kMenuToggleEnabled:
            focusController_.SetEnabled(!focusController_.settings.enabled);
            break;
        case kMenuToggleRankedBrightness:
            focusController_.SetRankedBrightnessEnabled(
                !focusController_.settings.rankedBrightnessEnabled
            );
            RefreshSettingsControls();
            break;
        case kMenuSettings:
            ShowSettingsWindow();
            break;
        case kMenuLaunchAtLogin:
            if (!SetLaunchAtLoginEnabled(!IsLaunchAtLoginEnabled())) {
                MessageBoxW(
                    messageWindow_,
                    L"无法修改登录启动设置。",
                    kAppName,
                    MB_OK | MB_ICONWARNING
                );
            }
            break;
        case kMenuCheckUpdates:
            StartUpdateCheck();
            break;
        case kMenuAbout:
            ShowAboutDialog();
            break;
        case kMenuQuit:
            DestroyWindow(messageWindow_);
            break;
        default:
            break;
        }
    }

    void ShowSettingsWindow() {
        if (settingsWindow_ == nullptr || !IsWindow(settingsWindow_)) {
            settingsWindow_ = CreateWindowExW(
                WS_EX_APPWINDOW,
                kSettingsWindowClass,
                L"FocusVeil 设置",
                WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                430,
                430,
                nullptr,
                nullptr,
                instance_,
                this
            );
        }
        RefreshSettingsControls();
        ShowWindow(settingsWindow_, SW_SHOWNORMAL);
        SetForegroundWindow(settingsWindow_);
    }

    void CreateSettingsControls(HWND hwnd) {
        HFONT font = reinterpret_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
        auto setFont = [font](HWND control) {
            SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
        };

        setFont(CreateWindowW(
            L"STATIC",
            L"背景压暗强度",
            WS_CHILD | WS_VISIBLE,
            24,
            22,
            160,
            20,
            hwnd,
            nullptr,
            instance_,
            nullptr
        ));
        setFont(CreateWindowW(
            L"STATIC",
            L"",
            WS_CHILD | WS_VISIBLE | SS_RIGHT,
            340,
            22,
            48,
            20,
            hwnd,
            reinterpret_cast<HMENU>(kDimmingValue),
            instance_,
            nullptr
        ));
        HWND dimmingTrack = CreateWindowW(
            TRACKBAR_CLASSW,
            L"",
            WS_CHILD | WS_VISIBLE | TBS_AUTOTICKS,
            24,
            48,
            364,
            32,
            hwnd,
            reinterpret_cast<HMENU>(kDimmingTrack),
            instance_,
            nullptr
        );
        setFont(dimmingTrack);
        SendMessageW(
            dimmingTrack,
            TBM_SETRANGE,
            TRUE,
            MAKELPARAM(kMinimumDimmingPercent, kMaximumDimmingPercent)
        );
        SendMessageW(dimmingTrack, TBM_SETTICFREQ, 10, 0);

        HWND rankedCheck = CreateWindowW(
            L"BUTTON",
            L"启用分级亮度",
            WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
            24,
            94,
            180,
            24,
            hwnd,
            reinterpret_cast<HMENU>(kRankedBrightnessCheck),
            instance_,
            nullptr
        );
        setFont(rankedCheck);

        setFont(CreateWindowW(
            L"STATIC",
            L"历史高亮窗口",
            WS_CHILD | WS_VISIBLE,
            24,
            132,
            160,
            20,
            hwnd,
            nullptr,
            instance_,
            nullptr
        ));
        setFont(CreateWindowW(
            L"STATIC",
            L"",
            WS_CHILD | WS_VISIBLE | SS_RIGHT,
            340,
            132,
            48,
            20,
            hwnd,
            reinterpret_cast<HMENU>(kHighlightCountValue),
            instance_,
            nullptr
        ));
        HWND countTrack = CreateWindowW(
            TRACKBAR_CLASSW,
            L"",
            WS_CHILD | WS_VISIBLE | TBS_AUTOTICKS,
            24,
            158,
            364,
            32,
            hwnd,
            reinterpret_cast<HMENU>(kHighlightCountTrack),
            instance_,
            nullptr
        );
        setFont(countTrack);
        SendMessageW(
            countTrack,
            TBM_SETRANGE,
            TRUE,
            MAKELPARAM(kMinimumHighlightWindowCount, kMaximumHighlightWindowCount)
        );
        SendMessageW(countTrack, TBM_SETTICFREQ, 1, 0);

        int top = 206;
        for (
            int level = kMinimumHighlightWindowCount;
            level <= kMaximumHighlightWindowCount;
            ++level
        ) {
            std::wstring label = L"第 " + std::to_wstring(level) + L" 层亮度";
            setFont(CreateWindowW(
                L"STATIC",
                label.c_str(),
                WS_CHILD | WS_VISIBLE,
                24,
                top,
                160,
                20,
                hwnd,
                nullptr,
                instance_,
                nullptr
            ));
            setFont(CreateWindowW(
                L"STATIC",
                L"",
                WS_CHILD | WS_VISIBLE | SS_RIGHT,
                340,
                top,
                48,
                20,
                hwnd,
                reinterpret_cast<HMENU>(kRankedBrightnessValueBase + level),
                instance_,
                nullptr
            ));
            HWND track = CreateWindowW(
                TRACKBAR_CLASSW,
                L"",
                WS_CHILD | WS_VISIBLE | TBS_AUTOTICKS,
                24,
                top + 24,
                364,
                30,
                hwnd,
                reinterpret_cast<HMENU>(kRankedBrightnessTrackBase + level),
                instance_,
                nullptr
            );
            setFont(track);
            SendMessageW(
                track,
                TBM_SETRANGE,
                TRUE,
                MAKELPARAM(
                    kMinimumRankedBrightnessPercent,
                    kMaximumRankedBrightnessPercent
                )
            );
            SendMessageW(track, TBM_SETTICFREQ, 10, 0);
            top += 42;
        }

        HWND resetButton = CreateWindowW(
            L"BUTTON",
            L"恢复默认分级亮度",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            24,
            376,
            168,
            28,
            hwnd,
            reinterpret_cast<HMENU>(kResetRankedBrightness),
            instance_,
            nullptr
        );
        setFont(resetButton);
    }

    void RefreshSettingsControls() {
        if (settingsWindow_ == nullptr || !IsWindow(settingsWindow_)) {
            return;
        }

        const Settings& settings = focusController_.settings;
        SetTrackbarPosition(kDimmingTrack, PercentFromAmount(settings.dimmingAmount));
        SetWindowTextW(
            GetDlgItem(settingsWindow_, kDimmingValue),
            PercentText(PercentFromAmount(settings.dimmingAmount)).c_str()
        );
        CheckDlgButton(
            settingsWindow_,
            kRankedBrightnessCheck,
            settings.rankedBrightnessEnabled ? BST_CHECKED : BST_UNCHECKED
        );
        SetTrackbarPosition(kHighlightCountTrack, settings.highlightWindowCount);
        SetWindowTextW(
            GetDlgItem(settingsWindow_, kHighlightCountValue),
            std::to_wstring(settings.highlightWindowCount).c_str()
        );

        EnableWindow(
            GetDlgItem(settingsWindow_, kHighlightCountTrack),
            settings.rankedBrightnessEnabled
        );
        EnableWindow(
            GetDlgItem(settingsWindow_, kResetRankedBrightness),
            settings.rankedBrightnessEnabled
        );

        for (
            int level = kMinimumHighlightWindowCount;
            level <= kMaximumHighlightWindowCount;
            ++level
        ) {
            int percent = PercentFromBrightness(
                settings.RankedBrightnessForLevel(level)
            );
            SetTrackbarPosition(kRankedBrightnessTrackBase + level, percent);
            SetWindowTextW(
                GetDlgItem(settingsWindow_, kRankedBrightnessValueBase + level),
                PercentText(percent).c_str()
            );
            EnableWindow(
                GetDlgItem(settingsWindow_, kRankedBrightnessTrackBase + level),
                settings.rankedBrightnessEnabled &&
                    level <= settings.highlightWindowCount
            );
        }
    }

    void SetTrackbarPosition(int identifier, int position) {
        HWND trackbar = GetDlgItem(settingsWindow_, identifier);
        if (trackbar != nullptr) {
            SendMessageW(trackbar, TBM_SETPOS, TRUE, position);
        }
    }

    int TrackbarPosition(int identifier) const {
        HWND trackbar = GetDlgItem(settingsWindow_, identifier);
        if (trackbar == nullptr) {
            return 0;
        }
        return static_cast<int>(SendMessageW(trackbar, TBM_GETPOS, 0, 0));
    }

    void HandleSettingsTrackbar(HWND trackbar) {
        if (trackbar == nullptr) {
            return;
        }
        int identifier = GetDlgCtrlID(trackbar);
        if (identifier == kDimmingTrack) {
            focusController_.SetDimmingAmount(
                AmountFromPercent(TrackbarPosition(kDimmingTrack))
            );
        } else if (identifier == kHighlightCountTrack) {
            focusController_.SetHighlightWindowCount(
                TrackbarPosition(kHighlightCountTrack)
            );
        } else if (
            identifier > kRankedBrightnessTrackBase &&
            identifier <= kRankedBrightnessTrackBase +
                kMaximumHighlightWindowCount
        ) {
            int level = identifier - kRankedBrightnessTrackBase;
            focusController_.SetRankedBrightnessForLevel(
                level,
                BrightnessFromPercent(TrackbarPosition(identifier))
            );
        }
        RefreshSettingsControls();
    }

    void HandleSettingsCommand(WORD command) {
        switch (command) {
        case kRankedBrightnessCheck:
            focusController_.SetRankedBrightnessEnabled(
                IsDlgButtonChecked(
                    settingsWindow_,
                    kRankedBrightnessCheck
                ) == BST_CHECKED
            );
            RefreshSettingsControls();
            break;
        case kResetRankedBrightness:
            focusController_.ResetRankedBrightnessLevels();
            RefreshSettingsControls();
            break;
        default:
            break;
        }
    }

    void ShowAboutDialog() {
        std::wstring message =
            L"FocusVeil Windows\n版本 " + std::wstring(kAppVersion) +
            L"\n\n应用根据窗口边界绘制透明遮罩，不截屏，也不读取窗口内容。";
        MessageBoxW(
            messageWindow_,
            message.c_str(),
            L"关于 FocusVeil",
            MB_OK | MB_ICONINFORMATION
        );
    }

    void StartUpdateCheck() {
        bool expected = false;
        if (!updateCheckInProgress_.compare_exchange_strong(expected, true)) {
            return;
        }

        if (updateThread_.joinable()) {
            updateThread_.join();
        }

        updateThread_ = std::thread([this]() {
            std::wstring message;
            std::wstring title = L"FocusVeil 更新";
            bool shouldOfferReleasePage = false;

            std::string json = ReadLatestReleaseJson();
            std::string tagName = ExtractJsonString(json, "tag_name");
            std::string htmlUrl = ExtractJsonString(json, "html_url");

            if (json.empty() || tagName.empty()) {
                message = L"无法读取 GitHub Releases 的最新版本信息。";
            } else {
                std::wstring latestTag = Utf8ToWide(tagName);
                int comparison = CompareVersions(kAppVersion, latestTag);
                if (comparison < 0) {
                    message =
                        L"发现新版本 " + latestTag +
                        L"。\n当前版本 " + std::wstring(kAppVersion) +
                        L"。\n是否打开发布页下载？";
                    shouldOfferReleasePage = true;
                } else {
                    message =
                        L"当前版本已经是最新版本。\n当前版本 " +
                        std::wstring(kAppVersion) + L"。";
                }
            }

            int result = MessageBoxW(
                nullptr,
                message.c_str(),
                title.c_str(),
                (shouldOfferReleasePage ? MB_YESNO : MB_OK) |
                    MB_ICONINFORMATION
            );
            if (shouldOfferReleasePage && result == IDYES) {
                std::wstring releaseUrl = htmlUrl.empty()
                    ? std::wstring(kRepositoryLatestReleaseUrl)
                    : Utf8ToWide(htmlUrl);
                OpenUrl(releaseUrl);
            }

            updateCheckInProgress_.store(false);
        });
    }
};

} // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int showCommand) {
    HANDLE mutex = CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
    if (mutex == nullptr) {
        return 1;
    }
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        MessageBoxW(
            nullptr,
            L"FocusVeil 已经在运行。",
            kAppName,
            MB_OK | MB_ICONINFORMATION
        );
        CloseHandle(mutex);
        return 0;
    }

    Application application;
    int result = application.Run(instance, showCommand);

    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return result;
}
