dotnet publish -c Release -o publish -r win-x64 /p:DefineConstants=WINDOWS /p:NativeLib=Shared /p:SelfContained=true
pause
