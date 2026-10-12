@echo off
setlocal enabledelayedexpansion
set "p=%~1"
set "p=%p:\=/%"
trash "%p%"
