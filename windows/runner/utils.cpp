#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>
#include <setupapi.h>
#include <initguid.h>
#include <devguid.h>
#include <hidsdi.h>

#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

// Helper function to format hexadecimal values
std::string formatHex(uint32_t value) {
    char buffer[20];
    sprintf_s(buffer, "0x%04X", value);
    return std::string(buffer);
}

// Tablet mode detection functions
bool IsTabletMode() {
    // Check if device is in tablet/slate mode
    return GetSystemMetrics(SM_CONVERTIBLESLATEMODE) == 0;
}

bool IsKeyboardAttached() {
    // Check if a physical keyboard is attached
    // This is a heuristic approach since Windows doesn't provide a direct API
    // We'll check for common keyboard device classes

    // Check for keyboard devices using SetupAPI
    HDEVINFO hDevInfo = SetupDiGetClassDevs(&GUID_DEVCLASS_KEYBOARD, NULL, NULL, DIGCF_PRESENT);
    if (hDevInfo == INVALID_HANDLE_VALUE) {
        return false;
    }

    SP_DEVINFO_DATA DeviceInfoData;
    DeviceInfoData.cbSize = sizeof(SP_DEVINFO_DATA);

    bool keyboardFound = false;
    for (DWORD i = 0; SetupDiEnumDeviceInfo(hDevInfo, i, &DeviceInfoData); i++) {
        // Check if this is a physical keyboard (not virtual)
        DWORD DataT;
        TCHAR buffer[1024];

        if (SetupDiGetDeviceRegistryProperty(
            hDevInfo,
            &DeviceInfoData,
            SPDRP_DEVICEDESC,
            &DataT,
            (PBYTE)buffer,
            sizeof(buffer),
            NULL)) {

            // Skip virtual keyboards
            std::wstring desc(buffer);
            if (desc.find(L"Virtual") == std::wstring::npos &&
                desc.find(L"Software") == std::wstring::npos) {
                keyboardFound = true;
                break;
            }
        }
    }

    SetupDiDestroyDeviceInfoList(hDevInfo);
    return keyboardFound;
}

bool HasTouchScreen() {
    // Check if device has touch screen capability
    return GetSystemMetrics(SM_DIGITIZER) != 0 &&
           GetSystemMetrics(SM_MAXIMUMTOUCHES) > 0;
}

int GetMaximumTouchPoints() {
    // Return the maximum number of touch points supported
    return GetSystemMetrics(SM_MAXIMUMTOUCHES);
}

bool IsConvertibleDevice() {
    // Check if this is a convertible (2-in-1) device
    // A convertible device can switch between tablet and laptop modes
    return GetSystemMetrics(SM_CONVERTIBLESLATEMODE) != 0 ||
           GetSystemMetrics(SM_TABLETPC) != 0;
}

// Debug function to log detailed input device information
std::string DebugLogInputDevices() {
    std::string result;
    UINT deviceCount = 0;

    // First call to get device count
    if (GetRawInputDeviceList(nullptr, &deviceCount, sizeof(RAWINPUTDEVICELIST)) != 0) {
        result = "ERROR: GetRawInputDeviceList failed to get device count\n";
        return result;
    }

    if (deviceCount == 0) {
        result = "INFO: No raw input devices found\n";
        return result;
    }

    result += "Found " + std::to_string(deviceCount) + " input devices:\n\n";

    // Allocate and get device list
    RAWINPUTDEVICELIST* devices = new RAWINPUTDEVICELIST[deviceCount];
    if (GetRawInputDeviceList(devices, &deviceCount, sizeof(RAWINPUTDEVICELIST)) == (UINT)-1) {
        result += "ERROR: GetRawInputDeviceList failed\n";
        delete[] devices;
        return result;
    }

    // Log each device with detailed information
    for (UINT i = 0; i < deviceCount; i++) {
        result += "Device " + std::to_string(i) + ":\n";

        // Get device name
        WCHAR deviceName[256] = {0};
        UINT nameSize = sizeof(deviceName);
        if (GetRawInputDeviceInfo(devices[i].hDevice, RIDI_DEVICENAME, deviceName, &nameSize) > 0) {
            char nameUtf8[512];
            WideCharToMultiByte(CP_UTF8, 0, deviceName, -1, nameUtf8, sizeof(nameUtf8), nullptr, nullptr);
            result += "  Name: " + std::string(nameUtf8) + "\n";
        } else {
            result += "  Name: <failed to retrieve>\n";
        }

        // Get detailed device information
        RID_DEVICE_INFO deviceInfo = {0};
        deviceInfo.cbSize = sizeof(RID_DEVICE_INFO);
        UINT deviceInfoSize = sizeof(deviceInfo);

        if (GetRawInputDeviceInfo(devices[i].hDevice, RIDI_DEVICEINFO, &deviceInfo, &deviceInfoSize) > 0) {
            result += "  Type: ";

            switch (deviceInfo.dwType) {
                case RIM_TYPEMOUSE:
                    result += "Mouse\n";
                    result += "  Mouse Info:\n";
                    result += "    NumberOfButtons: " + std::to_string(deviceInfo.mouse.dwNumberOfButtons) + "\n";
                    result += "    SampleRate: " + std::to_string(deviceInfo.mouse.dwSampleRate) + "\n";
                    result += "    HasWheel: ";
                    result += (deviceInfo.mouse.fHasHorizontalWheel ? "Yes" : "No");
                    result += "\n";
                    break;

                case RIM_TYPEKEYBOARD:
                    result += "Keyboard\n";
                    result += "  Keyboard Info:\n";
                    result += "    KeyboardMode: " + std::to_string(deviceInfo.keyboard.dwKeyboardMode) + "\n";
                    result += "    NumberOfFunctionKeys: " + std::to_string(deviceInfo.keyboard.dwNumberOfFunctionKeys) + "\n";
                    result += "    NumberOfIndicators: " + std::to_string(deviceInfo.keyboard.dwNumberOfIndicators) + "\n";
                    result += "    NumberOfKeysTotal: " + std::to_string(deviceInfo.keyboard.dwNumberOfKeysTotal) + "\n";
                    result += "    Type: " + std::to_string(deviceInfo.keyboard.dwType) + "\n";
                    break;

                case RIM_TYPEHID:
                    result += "HID\n";
                    result += "  HID Info:\n";
                    result += "    VendorId: " + formatHex(deviceInfo.hid.dwVendorId) + "\n";
                    result += "    ProductId: " + formatHex(deviceInfo.hid.dwProductId) + "\n";
                    result += "    VersionNumber: " + formatHex(deviceInfo.hid.dwVersionNumber) + "\n";
                    result += "    UsagePage: " + formatHex(deviceInfo.hid.usUsagePage) + "\n";
                    result += "    Usage: " + formatHex(deviceInfo.hid.usUsage) + "\n";
                    break;

                default:
                    result += "Unknown (" + std::to_string(deviceInfo.dwType) + ")\n";
            }
        } else {
            result += "  Device Info: <failed to retrieve>\n";
        }

        result += "\n";
    }

    delete[] devices;
    return result;
}

// Get a list of attached keyboard devices using proper HID classification
std::string GetKeyboardDevices() {
    std::string result;
    UINT deviceCount = 0;

    // First call to get device count
    if (GetRawInputDeviceList(nullptr, &deviceCount, sizeof(RAWINPUTDEVICELIST)) != 0) {
        result = "ERROR: GetRawInputDeviceList failed to get device count\n";
        return result;
    }

    if (deviceCount == 0) {
        result = "INFO: No raw input devices found\n";
        return result;
    }

    result += "Found keyboard devices:\n\n";

    // Allocate and get device list
    RAWINPUTDEVICELIST* devices = new RAWINPUTDEVICELIST[deviceCount];
    if (GetRawInputDeviceList(devices, &deviceCount, sizeof(RAWINPUTDEVICELIST)) == (UINT)-1) {
        result += "ERROR: GetRawInputDeviceList failed\n";
        delete[] devices;
        return result;
    }

    int keyboardDeviceCount = 0;

    // Log each device that is positively identified as a keyboard
    for (UINT i = 0; i < deviceCount; i++) {
        bool isKeyboard = false;

        // Get detailed device information
        RID_DEVICE_INFO deviceInfo = {0};
        deviceInfo.cbSize = sizeof(RID_DEVICE_INFO);
        UINT deviceInfoSize = sizeof(deviceInfo);

        if (GetRawInputDeviceInfo(devices[i].hDevice, RIDI_DEVICEINFO, &deviceInfo, &deviceInfoSize) > 0) {
            // Check if this is a keyboard device according to the specification
            if (deviceInfo.dwType == RIM_TYPEKEYBOARD) {
                // Standard keyboard device
                isKeyboard = true;
            } else if (deviceInfo.dwType == RIM_TYPEHID) {
                // HID device - check usage page and usage for keyboard classification
                if (deviceInfo.hid.usUsagePage == 0x0001 && deviceInfo.hid.usUsage == 0x0006) {
                    // HID keyboard (Usage Page: Generic Desktop, Usage: Keyboard)
                    isKeyboard = true;
                }
            }

            if (isKeyboard) {
                // Add this keyboard device to the results
                result += "Device " + std::to_string(keyboardDeviceCount) + ":\n";

                // Get device name
                WCHAR deviceName[256] = {0};
                UINT nameSize = sizeof(deviceName);
                if (GetRawInputDeviceInfo(devices[i].hDevice, RIDI_DEVICENAME, deviceName, &nameSize) > 0) {
                    char nameUtf8[512];
                    WideCharToMultiByte(CP_UTF8, 0, deviceName, -1, nameUtf8, sizeof(nameUtf8), nullptr, nullptr);
                    result += "  Name: " + std::string(nameUtf8) + "\n";
                } else {
                    result += "  Name: <failed to retrieve>\n";
                }

                // Add device type and specific information
                result += "  Type: ";
                switch (deviceInfo.dwType) {
                    case RIM_TYPEMOUSE:
                        result += "Mouse\n"; // This shouldn't happen if isKeyboard is true
                        break;
                    case RIM_TYPEKEYBOARD:
                        result += "Keyboard\n";
                        result += "  Keyboard Info:\n";
                        result += "    KeyboardMode: " + std::to_string(deviceInfo.keyboard.dwKeyboardMode) + "\n";
                        result += "    NumberOfFunctionKeys: " + std::to_string(deviceInfo.keyboard.dwNumberOfFunctionKeys) + "\n";
                        result += "    NumberOfIndicators: " + std::to_string(deviceInfo.keyboard.dwNumberOfIndicators) + "\n";
                        result += "    NumberOfKeysTotal: " + std::to_string(deviceInfo.keyboard.dwNumberOfKeysTotal) + "\n";
                        result += "    Type: " + std::to_string(deviceInfo.keyboard.dwType) + "\n";
                        break;
                    case RIM_TYPEHID:
                        result += "HID\n";
                        result += "  HID Info:\n";
                        result += "    VendorId: " + formatHex(deviceInfo.hid.dwVendorId) + "\n";
                        result += "    ProductId: " + formatHex(deviceInfo.hid.dwProductId) + "\n";
                        result += "    VersionNumber: " + formatHex(deviceInfo.hid.dwVersionNumber) + "\n";
                        result += "    UsagePage: " + formatHex(deviceInfo.hid.usUsagePage) + "\n";
                        result += "    Usage: " + formatHex(deviceInfo.hid.usUsage) + "\n";
                        break;
                    default:
                        result += "Unknown\n";
                }
                result += "\n";
                keyboardDeviceCount++;
            }
        }
    }

    delete[] devices;

    if (keyboardDeviceCount == 0) {
        result += "No keyboard devices found\n";
    }

    return result;
}
