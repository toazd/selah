#include <windows.h>
#include "flutter_window.h"
#include "utils.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/method_channel.h"
#include "flutter/event_channel.h"
#include "flutter/standard_method_codec.h"

#pragma comment(lib, "windowsapp.lib")

//#include <winrt/Windows.UI.ViewManagement.h>
//#include <winrt/Windows.UI.ViewManagement.Core.h>

//namespace winrt {
//using namespace Windows::UI::ViewManagement;
//using namespace Windows::UI::ViewManagement::Core;
//}


FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Set up a method channel to handle tablet mode detection
  tablet_mode_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.selah.tablet_mode",
      &flutter::StandardMethodCodec::GetInstance());
  tablet_mode_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name().compare("isTabletMode") == 0) {
      result->Success(flutter::EncodableValue(IsTabletMode()));
    } else if (call.method_name().compare("isKeyboardAttached") == 0) {
      result->Success(flutter::EncodableValue(IsKeyboardAttached()));
    } else if (call.method_name().compare("hasTouchScreen") == 0) {
      result->Success(flutter::EncodableValue(HasTouchScreen()));
    } else if (call.method_name().compare("getMaximumTouchPoints") == 0) {
      result->Success(flutter::EncodableValue(GetMaximumTouchPoints()));
    } else if (call.method_name().compare("getDeviceInfo") == 0) {
    flutter::EncodableMap device_info = {
        {flutter::EncodableValue("isTabletMode"), flutter::EncodableValue(IsTabletMode())},
        {flutter::EncodableValue("isKeyboardAttached"), flutter::EncodableValue(IsKeyboardAttached())},
        {flutter::EncodableValue("hasTouchScreen"), flutter::EncodableValue(HasTouchScreen())},
        {flutter::EncodableValue("maxTouchPoints"), flutter::EncodableValue(GetMaximumTouchPoints())},
        {flutter::EncodableValue("isConvertibleDevice"), flutter::EncodableValue(IsConvertibleDevice())}
      };
      result->Success(flutter::EncodableValue(device_info));
    } else if (call.method_name().compare("isConvertibleDevice") == 0) {
      result->Success(flutter::EncodableValue(IsConvertibleDevice()));
    } else if (call.method_name().compare("debugLogInputDevices") == 0) {
      std::string debugResult = DebugLogInputDevices();
      result->Success(flutter::EncodableValue(debugResult));
    } else if (call.method_name().compare("getKeyboardDevices") == 0) {
      std::string keyboardResult = GetKeyboardDevices();
      result->Success(flutter::EncodableValue(keyboardResult));
    } else {
      result->NotImplemented();
    }
  });

  // Set up a method channel to handle keyboard visibility.
  /*
  flutter::MethodChannel<> channel(
      flutter_controller_->engine()->messenger(), "com.selah.holybible/keyboard",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler([](const auto& call, auto result) {
    if (auto core_input_view = winrt::CoreInputView::GetForCurrentView()) {
      if (call.method_name().compare("showKeyboard") == 0) {
        if (!core_input_view.TryShowPrimaryView()) {
          result->Error("Error", "Failed to show keyboard.");
        }
      } else if (call.method_name().compare("hideKeyboard") == 0) {
        if (!core_input_view.TryHidePrimaryView()) {
          result->Error("Error", "Failed to hide keyboard.");
        }
      } else {
        result->NotImplemented();
      }
    } else {
      result->Error("Error", "Failed to get CoreInputView.");
    }
  });
  */

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// Helper function to translate Windows message IDs to names
/*
const char* GetWindowsMessageName(UINT message) {
  switch (message) {
    // Basic window messages  
    case 6: return "WM_ACTIVATE";
    case 16: return "WM_CLOSE";
    case 28: return "WM_ACTIVATEAPP";
    case 32: return "WM_SETCURSOR";
    case 33: return "WM_MOVE";
    case 70: return "WM_WINDOWPOSCHANGED";
    case 71: return "WM_WINDOWPOSCHANGING";
    case 127: return "WM_QUERYOPEN";
    case 132: return "WM_CTLCOLORBTN";
    case 134: return "WM_NCACTIVATE";
    case 160: return "WM_NCMOUSEMOVE";
    case 161: return "WM_NCLBUTTONDOWN";
    case 174: return "WM_SHOWWINDOW";
    
    // IME/Input Method Editor messages (OSK-related)
    case 578: return "WM_IME_STARTCOMPOSITION";
    case 579: return "WM_IME_ENDCOMPOSITION";
    case 585: return "WM_IME_COMPOSITION";
    case 586: return "WM_IME_KEYLAST";
    case 587: return "WM_IME_KEYDOWN";
    case 716: return "WM_IME_SETCONTEXT";  // KEY MESSAGE - sets IME context
    
    // Focus messages
    case 8: return "WM_KILLFOCUS";
    case 7: return "WM_SETFOCUS";
    
    // Notification messages
    case 528: return "WM_NOTIFY";
    case 274: return "WM_SYSCOMMAND";
    
    // Mouse messages
    case 513: return "WM_LBUTTONDOWN";
    case 514: return "WM_LBUTTONUP";
    case 515: return "WM_LBUTTONDBLCLK";
    case 512: return "WM_MOUSEMOVE";
    
    // Other control messages
    case 533: return "WM_UPDATEUISTATE";
    case 674: return "WM_USER";  // Custom user message
    
    // Unknown messages return nullptr
    default: return nullptr;
  }
}
*/

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Log ALL Windows messages for debugging
  // Comprehensive Windows message logging
  //std::cout << "MSG: " << message;
  
  // Get human-readable name if available
  // const char* msgName = GetWindowsMessageName(message);
  // if (msgName) {
  //   std::cout << " (" << msgName << ")";
  // } else {
  //   std::cout << " (UNKNOWN_MESSAGE)";
  // }
  
  // std::cout << " WPARAM: " << wparam << " LPARAM: " << lparam << std::endl;


  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SETTINGCHANGE: {
      // Debug: Log ALL WM_SETTINGCHANGE messages to see what's being received
      //std::wcout << L"WM_SETTINGCHANGE received. wparam: " << wparam << L", lparam: " << lparam;
      // if (lparam != 0) {
      //   std::wcout << L", lparam string: " << reinterpret_cast<wchar_t*>(lparam);
      // }
      //std::wcout << std::endl;

      if (lparam != 0 && wparam == 0) {
        const wchar_t* setting_name = reinterpret_cast<wchar_t*>(lparam);

        // Check for ALL tablet mode related setting changes
        bool isTabletModeChange = false;
        std::string change_type = "unknown";

        if (wcscmp(setting_name, L"TabletMode") == 0) {
          // Traditional tablet mode (older devices)
          isTabletModeChange = true;
          change_type = "TabletMode";
        } else if (wcscmp(setting_name, L"ConvertibleSlateMode") == 0) {
          // 2-in-1 convertible devices (like Surface Pro, Lenovo Yoga, etc.)
          isTabletModeChange = true;
          change_type = "ConvertibleSlateMode";
        } else if (wcscmp(setting_name, L"UserInteractionMode") == 0) {
          // User interaction method changes (touch vs keyboard/mouse)
          isTabletModeChange = true;
          change_type = "UserInteractionMode";
        }

        if (isTabletModeChange) {
          try {
            // Tablet mode has changed - notify Flutter through method channel
            bool currentTabletMode = IsTabletMode();
            //std::cout << "Tablet mode changed detected via " << change_type << ". Current mode: " << (currentTabletMode ? "Tablet" : "Laptop") << std::endl;

            if (tablet_mode_channel_) {
              //std::cout << "Attempting to invoke method channel..." << std::endl;
              tablet_mode_channel_->InvokeMethod("tabletModeChanged",
                                               std::make_unique<flutter::EncodableValue>(currentTabletMode));
              //std::cout << "Method channel invoked successfully for " << change_type << "." << std::endl;
            } else {
              //std::cout << "ERROR: tablet_mode_channel_ is null! Cannot notify Flutter of " << change_type << " change." << std::endl;
            }
          } catch (const std::exception& ){//e) {
            //std::cout << "EXCEPTION in " << change_type << " handling: " << e.what() << std::endl;
          } catch (...) {
            //std::cout << "UNKNOWN EXCEPTION in " << change_type << " handling!" << std::endl;
          }
        } else {
          //std::wcout << L"WM_SETTINGCHANGE received but not tablet-mode related. Parameter: " << setting_name << std::endl;
        }
      } else {
        //std::cout << "WM_SETTINGCHANGE received with invalid parameters (lparam=0 or wparam!=0)" << std::endl;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
