# BuildTargets.cmake - source collection, executables, per-target flags + linking.

file(GLOB_RECURSE KEEPERFX_SOURCES_C   CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/src/*.c")
file(GLOB_RECURSE KEEPERFX_SOURCES_CXX CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/src/*.cpp")

# Functional-test harness is off by default (FTEST_DEBUG defaults to 0).
list(FILTER KEEPERFX_SOURCES_C   EXCLUDE REGEX "/src/ftests/")
list(FILTER KEEPERFX_SOURCES_CXX EXCLUDE REGEX "/src/ftests/")

# Platform filtering (matches the hand Makefiles).
if(KFX_UWP)
    list(FILTER KEEPERFX_SOURCES_CXX EXCLUDE REGEX "/PlatformLinux\\.cpp$")
    list(FILTER KEEPERFX_SOURCES_CXX EXCLUDE REGEX "/PlatformWindows\\.cpp$")
    list(FILTER KEEPERFX_SOURCES_CXX EXCLUDE REGEX "/WindowCompositorWin\\.cpp$")
elseif(WIN32)
    list(FILTER KEEPERFX_SOURCES_CXX EXCLUDE REGEX "/PlatformLinux\\.cpp$")
    list(FILTER KEEPERFX_SOURCES_CXX EXCLUDE REGEX "/PlatformUWP\\.cpp$")
elseif(UNIX AND NOT APPLE)
    list(FILTER KEEPERFX_SOURCES_CXX EXCLUDE REGEX "/PlatformWindows\\.cpp$")
    list(FILTER KEEPERFX_SOURCES_CXX EXCLUDE REGEX "/WindowCompositorWin\\.cpp$")
    list(FILTER KEEPERFX_SOURCES_CXX EXCLUDE REGEX "/PlatformUWP\\.cpp$")
endif()

# Window icon
if(NOT WIN32)
    set(KFX_ICON_PNG "${CMAKE_SOURCE_DIR}/res/keeperfx_icon256-24bpp.png")
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${KFX_ICON_PNG}")
    file(READ "${KFX_ICON_PNG}" _icon_hex HEX)
    string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," _icon_bytes "${_icon_hex}")
    set(KFX_ICON_C "${CMAKE_BINARY_DIR}/generated/window_icon.c")
    file(WRITE "${KFX_ICON_C}.in"
        "const unsigned char kfx_window_icon_png[] = {${_icon_bytes}};\n"
        "const unsigned int kfx_window_icon_png_size = sizeof(kfx_window_icon_png);\n")
    configure_file("${KFX_ICON_C}.in" "${KFX_ICON_C}" COPYONLY)
    list(APPEND KEEPERFX_SOURCES_C "${KFX_ICON_C}")
endif()

if(KFX_UWP)
    # One app package. The verbose-logging variant is a cache switch instead of
    # a second executable, since each UWP executable is a whole app package.
    option(KFX_UWP_HVLOG "UWP: build with verbose logging (BFDEBUG_LEVEL=10)" OFF)
    set(KFX_UWP_PUBLISHER "CN=KeeperFX" CACHE STRING
        "UWP: Identity Publisher in Package.appxmanifest; must match the signing certificate's subject")
    configure_file("${CMAKE_SOURCE_DIR}/build/uwp/Package.appxmanifest.in"
                   "${CMAKE_BINARY_DIR}/uwp/Package.appxmanifest" @ONLY)
    file(GLOB KFX_UWP_ASSETS CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/build/uwp/Assets/*.png")
    set_property(SOURCE ${KFX_UWP_ASSETS} PROPERTY VS_DEPLOYMENT_CONTENT 1)
    set_property(SOURCE ${KFX_UWP_ASSETS} PROPERTY VS_DEPLOYMENT_LOCATION "Assets")
    # CA bundle for curl (OpenSSL on UWP can't use the Windows certificate
    # store), installed at the package root; see net_matchmaking.c.
    set(KFX_UWP_CACERT "${CMAKE_BINARY_DIR}/uwp/cacert.pem")
    if(NOT EXISTS "${KFX_UWP_CACERT}")
        file(DOWNLOAD "https://curl.se/ca/cacert.pem" "${KFX_UWP_CACERT}" TLS_VERIFY ON STATUS _kfx_ca_status)
        list(GET _kfx_ca_status 0 _kfx_ca_rc)
        if(NOT _kfx_ca_rc EQUAL 0)
            file(REMOVE "${KFX_UWP_CACERT}")
            message(FATAL_ERROR "Could not download https://curl.se/ca/cacert.pem: ${_kfx_ca_status}")
        endif()
    endif()
    set_property(SOURCE "${KFX_UWP_CACERT}" PROPERTY VS_DEPLOYMENT_CONTENT 1)
    add_executable(keeperfx WIN32 ${KEEPERFX_SOURCES_C} ${KEEPERFX_SOURCES_CXX}
        "${CMAKE_BINARY_DIR}/uwp/Package.appxmanifest" ${KFX_UWP_ASSETS} "${KFX_UWP_CACERT}")
    target_compile_definitions(keeperfx PUBLIC BFDEBUG_LEVEL=$<IF:$<BOOL:${KFX_UWP_HVLOG}>,10,0>)
    set(KFX_TARGETS keeperfx)
else()
    add_executable(keeperfx       ${KEEPERFX_SOURCES_C} ${KEEPERFX_SOURCES_CXX})
    add_executable(keeperfx_hvlog ${KEEPERFX_SOURCES_C} ${KEEPERFX_SOURCES_CXX})
    target_compile_definitions(keeperfx       PUBLIC BFDEBUG_LEVEL=0)
    target_compile_definitions(keeperfx_hvlog PUBLIC BFDEBUG_LEVEL=10)
    set(KFX_TARGETS keeperfx keeperfx_hvlog)
endif()

if(WIN32 AND NOT KFX_UWP)
    foreach(_t IN LISTS KFX_TARGETS)
        target_sources(${_t} PRIVATE "${CMAKE_SOURCE_DIR}/res/keeperfx_stdres.rc")
    endforeach()

    # bfd is slow; prefer LLD when it's actually available (LINKER_TYPE needs
    # CMake >= 3.29, harmlessly ignored on older CMake). MSYS2 doesn't ship an
    # i686 lld at all (only mingw64/ucrt64/clang64), so forcing LLD
    # unconditionally breaks the 32-bit MinGW build with "collect2.exe: fatal
    # error: cannot find 'ld'" - detect it instead of assuming it's there.
    find_program(KFX_LLD_LINKER NAMES ld.lld ld.lld.exe)
    if(KFX_LLD_LINKER)
        foreach(_t IN LISTS KFX_TARGETS)
            set_property(TARGET ${_t} PROPERTY LINKER_TYPE LLD)
        endforeach()
    endif()

    if(NOT MSVC)
        # keeperfx.exe itself is statically linked against libgcc/libstdc++
        # (see apply_keeperfx_link_flags), but vcpkg builds its own packages
        # (openal-soft, fmt) with that toolchain's own default flags, which
        # link them dynamically against libgcc_s_dw2-1.dll/libstdc++-6.dll/
        # libwinpthread-1.dll. Those normally live alongside the compiler
        # itself in a standard MinGW layout - copy them next to the exe so
        # the game can actually launch (no install step needed for this).
        get_filename_component(_kfx_mingw_bin "${CMAKE_CXX_COMPILER}" DIRECTORY)
        foreach(_t IN LISTS KFX_TARGETS)
            foreach(_dll libgcc_s_dw2-1.dll libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll)
                if(EXISTS "${_kfx_mingw_bin}/${_dll}")
                    add_custom_command(TARGET ${_t} POST_BUILD
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                            "${_kfx_mingw_bin}/${_dll}" "$<TARGET_FILE_DIR:${_t}>"
                        VERBATIM)
                endif()
            endforeach()
        endforeach()
    endif()
endif()

foreach(_t IN LISTS KFX_TARGETS)
    # Put src/ on the include path so sources in subdirectories (src/kfx/platform/, ...)
    # can use "pre_inc.h" and "kfx/platform/Foo.h" style includes.
    target_include_directories(${_t} PRIVATE "${CMAKE_SOURCE_DIR}/src")
    apply_keeperfx_warnings(${_t})
    apply_keeperfx_link_flags(${_t})
    kfx_link_dependencies(${_t})
    apply_windows_system_libs(${_t})
    apply_keeperfx_debug_split(${_t})
    # Tracy profiler (FetchContent target — compiled from source, matches CRT).
    if(KEEPERFX_TRACY AND TARGET TracyClient)
        target_link_libraries(${_t} PRIVATE TracyClient)
    endif()
endforeach()

kfx_status("BUILD" "${CMAKE_CXX_COMPILER_ID} -> keeperfx, keeperfx_hvlog")

# Save format tests (tests/save): links only the save codec, the field tables and zlib, no game code.
# Off by default. Build with -DKFX_SAVE_TESTS=ON, run with ctest.
option(KFX_SAVE_TESTS "Build the save format tests (kfx_save_tests)" OFF)
if(KFX_SAVE_TESTS)
    enable_testing()
    file(GLOB KFX_SAVE_SOURCES CONFIGURE_DEPENDS
        "${CMAKE_SOURCE_DIR}/src/kfx/save/core/*.cpp" "${CMAKE_SOURCE_DIR}/src/kfx/save/core/schema/*.c")
    add_executable(kfx_save_tests
        "${CMAKE_SOURCE_DIR}/tests/save/kfx_save_tests.c"
        "${CMAKE_SOURCE_DIR}/tools/save-tool/save_digest.c"
        "${CMAKE_SOURCE_DIR}/tools/save-tool/save_validate.c"
        ${KFX_SAVE_SOURCES})
    target_include_directories(kfx_save_tests PRIVATE
        "${CMAKE_SOURCE_DIR}/src" "${CMAKE_SOURCE_DIR}/tools/save-tool" "${KFX_CENTITOML_SRC}"
        $<TARGET_PROPERTY:kfx_sdl3,INTERFACE_INCLUDE_DIRECTORIES>)
    target_compile_definitions(kfx_save_tests PRIVATE BFDEBUG_LEVEL=0 DEBUG=0)
    if(WIN32)
        target_link_libraries(kfx_save_tests PRIVATE zlib_static)
    else()
        target_link_libraries(kfx_save_tests PRIVATE PkgConfig::ZLIB)
    endif()
    add_test(NAME kfx_save_tests COMMAND kfx_save_tests)
    kfx_status("TESTS" "kfx_save_tests (ctest)")
endif()
