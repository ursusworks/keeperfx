<#
.SYNOPSIS
    Builds LuaJIT as a static library for UWP x64 (Xbox Developer Mode).

.DESCRIPTION
    vcpkg's luajit port does not support UWP, so this does what LuaJIT's own
    src/msvcbuild.bat does, with two changes:
      * the library is compiled for the UWP API family (_UWP, which LuaJIT
        supports natively, and WINAPI_FAMILY_APP);
      * the JIT compiler is left out (LUAJIT_DISABLE_JIT). UWP only allows
        executable memory with the codeGeneration capability, and KeeperFX's
        Lua scripts are light enough for the interpreter.
    The host tools (minilua, buildvm) are built as normal desktop programs,
    because they run on this PC during the build.

    Output: <OutDir>\include\*.h and <OutDir>\lib\lua51.lib. Pass OutDir to
    CMake as -DKFX_LUAJIT_DIR (the uwp-x64 preset uses out\luajit-uwp).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build\uwp\build-luajit.ps1
#>
param(
    [string]$OutDir = (Join-Path $PSScriptRoot "..\..\out\luajit-uwp"),
    [string]$WorkDir = (Join-Path $PSScriptRoot "..\..\out\luajit-src"),
    # LuaJIT v2.1 branch, pinned. Bump deliberately.
    [string]$Commit = "63c8f1a9b479ba5518cf6a170ff7729178bc3cfd"
)
$ErrorActionPreference = "Stop"

$OutDir  = [IO.Path]::GetFullPath($OutDir)
$WorkDir = [IO.Path]::GetFullPath($WorkDir)

# --- Visual Studio environment ----------------------------------------------------
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found; install Visual Studio 2022 with 'Desktop development with C++' and 'Universal Windows Platform development'." }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "No Visual Studio with the x64 C++ tools found." }
$vcvars = Join-Path $vs "VC\Auxiliary\Build\vcvars64.bat"

# --- Sources ----------------------------------------------------------------------
if (-not (Test-Path (Join-Path $WorkDir ".git"))) {
    git clone https://github.com/LuaJIT/LuaJIT.git $WorkDir
    if ($LASTEXITCODE) { throw "git clone failed" }
}
git -C $WorkDir fetch --quiet origin
git -C $WorkDir checkout --quiet --force $Commit
if ($LASTEXITCODE) { throw "git checkout $Commit failed" }
git -C $WorkDir clean -fdxq

# --- Build ------------------------------------------------------------------------
# Host tools: plain desktop flags. Target library: UWP flags.
# HOSTCC gets LUAJIT_DISABLE_JIT too, so buildvm generates the interpreter-only
# VM tables that match the library.
$bat = @'
@echo off
setlocal
cd /d "%~dp0src"
set HOSTCC=cl /nologo /c /O2 /W3 /MD /D_CRT_SECURE_NO_DEPRECATE /DLUAJIT_DISABLE_JIT
set TARGETCC=cl /nologo /c /O2 /W3 /MD /Z7 /D_CRT_SECURE_NO_DEPRECATE /DLUAJIT_DISABLE_JIT /D_UWP /DWINAPI_FAMILY=WINAPI_FAMILY_APP
set ALL_LIB=lib_base.c lib_math.c lib_bit.c lib_string.c lib_table.c lib_io.c lib_os.c lib_package.c lib_debug.c lib_jit.c lib_ffi.c lib_buffer.c

%HOSTCC% host\minilua.c || exit /b 1
link /nologo /out:minilua.exe minilua.obj || exit /b 1
rem Same as msvcbuild.bat for x64, minus "-D JIT".
minilua ..\dynasm\dynasm.lua -LN -D WIN -D FFI -D ENDIAN_LE -D FPU -D P64 -o host\buildvm_arch.h vm_x64.dasc || exit /b 1
git show -s --format=%%ct >luajit_relver.txt
minilua host\genversion.lua || exit /b 1

%HOSTCC% /I "." /I ..\dynasm host\buildvm*.c || exit /b 1
link /nologo /out:buildvm.exe buildvm*.obj || exit /b 1
buildvm -m peobj -o lj_vm.obj || exit /b 1
buildvm -m bcdef -o lj_bcdef.h %ALL_LIB% || exit /b 1
buildvm -m ffdef -o lj_ffdef.h %ALL_LIB% || exit /b 1
buildvm -m libdef -o lj_libdef.h %ALL_LIB% || exit /b 1
buildvm -m recdef -o lj_recdef.h %ALL_LIB% || exit /b 1
buildvm -m vmdef -o jit\vmdef.lua %ALL_LIB% || exit /b 1
buildvm -m folddef -o lj_folddef.h lj_opt_fold.c || exit /b 1
del /q minilua.obj buildvm*.obj

%TARGETCC% lj_*.c lib_*.c || exit /b 1
lib /nologo /nodefaultlib /OUT:lua51.lib lj_*.obj lib_*.obj || exit /b 1
echo === LuaJIT for UWP x64 built ===
'@
$batPath = Join-Path $WorkDir "build-uwp.bat"
Set-Content -Path $batPath -Value $bat -Encoding ASCII

cmd /c "`"$vcvars`" >nul && `"$batPath`""
if ($LASTEXITCODE) { throw "LuaJIT build failed (exit code $LASTEXITCODE)" }

# --- Install ----------------------------------------------------------------------
$inc = Join-Path $OutDir "include"
$lib = Join-Path $OutDir "lib"
New-Item -ItemType Directory -Force -Path $inc, $lib | Out-Null
foreach ($h in "lua.h", "lualib.h", "lauxlib.h", "luaconf.h", "lua.hpp", "luajit.h") {
    Copy-Item (Join-Path $WorkDir "src\$h") $inc -Force
}
Copy-Item (Join-Path $WorkDir "src\lua51.lib") $lib -Force
Write-Host "LuaJIT for UWP installed to $OutDir"
