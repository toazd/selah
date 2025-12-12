# iOS Build Instructions for Selah

## Overview
This guide explains how to use the GitHub Actions workflow to build iOS debug versions of the Selah app for testing on your iPhone XR via Sideloadly.

## Prerequisites
- ✅ Private GitHub repository set up
- ✅ iPhone XR for testing
- ✅ Sideloadly installed on your computer
- ✅ GitHub repository with the workflow file

## How to Build the iOS App

### 1. Trigger the Build
1. Go to your GitHub repository: `https://github.com/toazd/selah`
2. Click on the **"Actions"** tab
3. In the left sidebar, you'll see **"Build iOS App"**
4. Click on **"Build iOS App"** workflow
5. Click the **"Run workflow"** button (green button on the right)
6. Optionally add a build number or description
7. Click **"Run workflow"** to start the build

### 2. Monitor the Build
- The build will take approximately 5-10 minutes
- You can monitor progress in real-time
- Look for the **"Build iOS App"** job running on **macos-latest**

### 3. Download the IPA File
When the build completes successfully:
1. Go to the completed workflow run
2. Scroll down to the **"Artifacts"** section
3. You'll see a file named `selah-ios-debug-[BUILD_NUMBER]`
4. Click on it to download the IPA file
5. Save it to an easily accessible location (e.g., Desktop)

## Installing via Sideloadly

### Step 1: Prepare Sideloadly
1. Open **Sideloadly** on your computer
2. Connect your **iPhone XR** via USB cable
3. Ensure your iPhone is unlocked and trusted

### Step 2: Install the App
1. In Sideloadly, you'll see your iPhone listed
2. **Drag and drop** the downloaded IPA file onto Sideloadly
3. Sideloadly will prompt for your Apple ID
4. Enter your Apple ID credentials
5. Wait for the installation to complete (1-3 minutes)

### Step 3: Trust the App on iPhone
1. On your iPhone, go to **Settings > General > VPN & Device Management**
2. Find the developer profile associated with your Apple ID
3. Tap on it and select **"Trust [Your Apple ID]"**
4. Confirm by tapping **"Trust"** again

### Step 4: Launch the App
1. The app should now appear on your iPhone home screen
2. Tap the **"Selah"** app icon to launch
3. You may need to allow permissions (notifications, etc.)

## Important Notes

### Build Limitations
- **Free Provisioning**: Uses temporary provisioning profiles valid for 7 days
- **Apple ID Required**: You'll need your Apple ID for installation
- **Device Limit**: Free provisioning works on devices associated with your Apple ID

### Firebase Configuration
- ✅ **Authentication**: Will work with your existing Firebase project
- ✅ **Firestore**: Database functionality fully enabled
- ✅ **All Features**: Complete app functionality preserved

### Troubleshooting

#### Installation Fails
1. **Restart iPhone** and try again
2. **Check Apple ID**: Ensure correct credentials
3. **USB Connection**: Try different cable/port
4. **Trust Profile**: Make sure to trust the developer profile

#### App Crashes
1. **Check iOS Version**: Ensure iPhone XR is on iOS 12+
2. **Reinstall**: Delete app and reinstall
3. **Check Logs**: Look for crash reports in Settings > Privacy & Security > Analytics & Improvements

#### Build Issues
1. **Check Firebase Config**: Ensure `firebase.json` is properly configured
2. **Dependencies**: Make sure `pubspec.yaml` has all required dependencies
3. **iOS Deployment Target**: Check `ios/Flutter/AppFrameworkInfo.plist`

## Usage Statistics
- **GitHub Actions Minutes**: ~10-15 minutes per build
- **Monthly Limit**: 500 minutes for private repositories
- **Recommended**: Build 2-3 times per month to stay within limits

## Next Steps
1. **Test thoroughly** on your iPhone XR
2. **Report any issues** you encounter
3. **Consider upgrading** to Apple Developer account ($99/year) for:
   - Longer-lasting provisioning profiles
   - App Store distribution
   - More advanced testing features

## Support
If you encounter issues:
1. Check the GitHub Actions logs for error messages
2. Ensure all dependencies are properly configured
3. Verify your iPhone XR meets minimum iOS requirements
4. Contact support if Firebase integration issues persist

---
**Last Updated**: December 12, 2025
**Workflow Version**: 1.0
**Supported iOS Version**: iOS 12.0+
