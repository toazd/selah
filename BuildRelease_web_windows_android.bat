@echo off
REM No longer need since the migration from firebase to supabase
REM CALL mkdir "C:\Users\wmcdannell\Documents\Bible Study\Apps\Selah_dev\selah\build\windows\x64"
REM CALL copy /Y "C:\Users\wmcdannell\Documents\Bible Study\Apps\Selah_dev\_build_windows_x64\firebase_cpp_sdk_windows_12.7.0.zip" "C:\Users\wmcdannell\Documents\Bible Study\Apps\Selah_dev\selah\build\windows\x64"

REM cd "C:\Users\wmcdannell\Documents\Bible Study\Apps\Selah_dev\selah"
CALL flutter build web --release
CALL flutter build windows --release
CALL flutter build apk --release
