# Platforms.cmake - platform detection + directory-scope compile definitions.

# UWP (Xbox Developer Mode / Windows Store app): configure with
# -DCMAKE_SYSTEM_NAME=WindowsStore -DCMAKE_SYSTEM_VERSION=10.0 -A x64,
# see docs/xbox-uwp.md. WIN32 is also true here, so test KFX_UWP first.
if(CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
    set(KFX_UWP TRUE)
    if(NOT MSVC)
        message(FATAL_ERROR "The UWP build needs the MSVC toolset (Visual Studio 2022 with the UWP workload)")
    endif()
    if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
        message(FATAL_ERROR "The UWP build is x64 only (Xbox One / Series are x64); configure with -A x64")
    endif()
    kfx_status("PLATFORM" "Universal Windows Platform (x64, MSVC)")
    # Engine-side defines and flags are applied per target, so they don't leak
    # into SDL and the other FetchContent dependencies: see
    # apply_keeperfx_warnings() in Helpers.cmake.
elseif(WIN32)
    kfx_status("PLATFORM" "Windows / MinGW-w64 (i686)")
elseif(UNIX AND NOT APPLE)
    kfx_status("PLATFORM" "Linux (x86_64)")
else()
    message(FATAL_ERROR "Unsupported platform (only Windows/MinGW and Linux are supported)")
endif()

add_compile_definitions("DEBUG=$<IF:$<CONFIG:Debug>,1,0>")

option(KEEPERFX_TRACY "Enable Tracy profiler instrumentation" OFF)

option(KFX_SPLIT_DEBUG
    "Linux: move debug info out of the binaries into <binary>.debug files (always on for MinGW)" OFF)

# Static-linkage defines for the prebuilt Windows dependencies.
if(WIN32 AND NOT KFX_UWP)
    add_compile_definitions(_CRT_NONSTDC_NO_WARNINGS _CRT_SECURE_NO_WARNINGS)
    # AL_LIBTYPE_STATIC tells <AL/al.h> not to mark its functions dllimport.
    # Needed when linking the kfx-deps static prebuilt (mirrors the Makefile);
    # not needed -- and not defined -- when vcpkg's openal-soft is in play,
    # which is linked dynamically. See Dependencies.cmake for why the two
    # differ.
    if(NOT VCPKG_TOOLCHAIN)
        add_compile_definitions(AL_LIBTYPE_STATIC)
    endif()
    add_compile_definitions(SPNG_STATIC=1)
    # MSVC's <math.h> only defines M_PI/M_E/etc. when this is set before the
    # first include; MinGW's <math.h> defines them unconditionally regardless,
    # so this is a no-op there. Directory-scope since math.h can be pulled in
    # transitively in an unpredictable order across source files.
    add_compile_definitions(_USE_MATH_DEFINES)
endif()
