@echo off

setlocal

REM Define source and destination directories
set "source_dir=E:\Workspace\flutter\PicaComic\build\windows\x64\runner\Release"
set "destination_dir=E:\Program Files\PicaComic"

echo Copying files from %source_dir% to %destination_dir%
REM Copy files from source to destination with overwrite
xcopy "%source_dir%\*" "%destination_dir%\" /s /e /y

REM End of script
endlocal