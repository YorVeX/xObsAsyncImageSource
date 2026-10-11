@echo off

for %%I in (..\.) do set "ProjectName=%%~nI"
if "%ProjectName%"=="" exit /b 1

REM OBS Studio 33+ loads third party plugins from <root>\plugins\<name>\<name>.dll with the data in <name>\data,
REM so the archive can be extracted either into C:\ProgramData\obs-studio or into a portable OBS Studio root folder

REM Remove the folders of the layout used before OBS Studio 33.0
if exist ..\release\win-x64\obs-plugins rmdir /s /q ..\release\win-x64\obs-plugins
if exist ..\release\win-x64\data rmdir /s /q ..\release\win-x64\data
if exist ..\release\win-x64\plugins\%ProjectName% rmdir /s /q ..\release\win-x64\plugins\%ProjectName%

mkdir ..\release\win-x64\plugins\%ProjectName%\data\locale
copy /Y ..\publish\win-x64\* ..\release\win-x64\plugins\%ProjectName%\
copy /Y ..\locale\* ..\release\win-x64\plugins\%ProjectName%\data\locale\