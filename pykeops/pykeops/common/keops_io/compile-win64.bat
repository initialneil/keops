@echo off
set PWD=%~dp0
set BUILD_DIR=%PWD%build
echo %BUILD_DIR%

if (%1) NEQ () (
  set VCVARS64=%1
)
if (%2) NEQ () (
  set PYBIND11_DIR=%2
)

if ((%VCVARS64%) == ()) (
  echo "VCVARS64 not set, please add environ variable to vcvars64.bat"
  set VCVARS64="C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
)
if ((%VCVARS64%) == ("")) (
  echo "VCVARS64 not set, please add environ variable to vcvars64.bat"
  set VCVARS64="C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
)

REM python -m pybind11 --cmakedir
REM C:\ProgramData\Anaconda3\envs\pt1.11_cu11.3\lib\site-packages\pybind11\share\cmake\pybind11
if (%PYBIND11_DIR%)==() (
  set PYBIND11_DIR="C:\ProgramData\Anaconda3\envs\pt1.11_cu11.3\lib\site-packages\pybind11\share\cmake\pybind11"
)
if (%PYBIND11_DIR%)==("") (
  set PYBIND11_DIR="C:\ProgramData\Anaconda3\envs\pt1.11_cu11.3\lib\site-packages\pybind11\share\cmake\pybind11"
)

echo --------------------------------------------------
echo User defined path:
echo VCVARS64 = %VCVARS64%
echo PYBIND11_DIR = %PYBIND11_DIR%
echo --------------------------------------------------

REM enable vs
call %VCVARS64%

REM cmake
cd /D %BUILD_DIR%

cmake ../ -G Ninja -Dpybind11_DIR=%PYBIND11_DIR%

REM build
ninja -v

REM pause
