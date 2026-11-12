# DependenciesUWP.cmake - third-party libraries for the UWP (Xbox Developer
# Mode / Windows Store) build. Included from Dependencies.cmake when KFX_UWP.
#
# Where each dependency comes from, and why:
#
#   SDL3, SDL3_mixer, SDL3_image  FetchContent. Upstream SDL3 dropped the WinRT
#                                 backend, so SDL3 comes from SternXD/SDL3-uwp,
#                                 a maintained fork that keeps it (3.4.x). Built
#                                 as DLLs: SDL's WinRT code is C++/CX (/ZW), which
#                                 cannot be linked statically into a non-/ZW exe.
#                                 The DLLs are ProjectReferences of keeperfx, so
#                                 Visual Studio puts them into the app package.
#   zlib, minizip, libspng,       vcpkg, triplet x64-uwp-static-md (static libs,
#   ffmpeg, openal-soft, curl     dynamic CRT), manifest in build/uwp/vcpkg.json.
#   LuaJIT                        vcpkg's port is !uwp; build it with
#                                 build/uwp/build-luajit.ps1 (LuaJIT has its own
#                                 _UWP support) and pass -DKFX_LUAJIT_DIR=...
#   enet6, centijson, astronomy   FetchContent from the same sources kfx-deps
#                                 builds; enet6 gets a small UWP patch.
#   miniupnpc, libnatpmp          Not built: they need desktop-only networking
#                                 APIs. net_portforward.cpp is a stub on UWP.

include(FetchContent)

set(KFX_UWP_PATCHES "${CMAKE_SOURCE_DIR}/build/uwp/patches")

# Pinned so a force-push upstream can't change what we build.
set(KFX_SDL3_UWP_REPO   "https://github.com/SternXD/SDL3-uwp.git" CACHE STRING "SDL3 fork with the WinRT/UWP backend")
set(KFX_SDL3_UWP_COMMIT "ec2e0e7c77ec9a04437eb3ae884d62ae0e6129b4" CACHE STRING "Commit of KFX_SDL3_UWP_REPO to build (3.4.20)")
set(SDL3_MIX_VER  3.2.4)
set(SDL3_IMG_VER  3.4.6)

# --- SDL3 (WinRT backend) ------------------------------------------------------
set(SDL_SHARED        ON  CACHE BOOL "" FORCE)
set(SDL_STATIC        OFF CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY  OFF CACHE BOOL "" FORCE)
set(SDL_TESTS         OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES      OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL       OFF CACHE BOOL "" FORCE)
FetchContent_Declare(SDL3
    GIT_REPOSITORY "${KFX_SDL3_UWP_REPO}"
    GIT_TAG        "${KFX_SDL3_UWP_COMMIT}")

# --- SDL3_mixer: WAV samples + Ogg Vorbis music, using the built-in decoders --
set(SDLMIXER_VENDORED   OFF CACHE BOOL "" FORCE)
set(SDLMIXER_DEPS_SHARED OFF CACHE BOOL "" FORCE)
set(SDLMIXER_SAMPLES    OFF CACHE BOOL "" FORCE)
set(SDLMIXER_EXAMPLES   OFF CACHE BOOL "" FORCE)
set(SDLMIXER_TESTS      OFF CACHE BOOL "" FORCE)
set(SDLMIXER_INSTALL    OFF CACHE BOOL "" FORCE)
set(SDLMIXER_WAVE       ON  CACHE BOOL "" FORCE)
set(SDLMIXER_VORBIS_STB ON  CACHE BOOL "" FORCE)
set(SDLMIXER_MP3        ON  CACHE BOOL "" FORCE)   # dr_mp3 (built in)
set(SDLMIXER_MP3_MPG123 OFF CACHE BOOL "" FORCE)
set(SDLMIXER_FLAC       ON  CACHE BOOL "" FORCE)   # dr_flac (built in)
set(SDLMIXER_FLAC_LIBFLAC OFF CACHE BOOL "" FORCE)
foreach(_off VORBIS_VORBISFILE VORBIS_TREMOR OPUS WAVPACK GME MOD MIDI MIDI_FLUIDSYNTH)
    set(SDLMIXER_${_off} OFF CACHE BOOL "" FORCE)
endforeach()
FetchContent_Declare(SDL3_mixer
    URL "https://github.com/libsdl-org/SDL_mixer/releases/download/release-${SDL3_MIX_VER}/SDL3_mixer-${SDL3_MIX_VER}.tar.gz")

# --- SDL3_image: PNG load via stb_image, PNG save via SDL core ----------------
set(SDLIMAGE_VENDORED    OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_DEPS_SHARED OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_SAMPLES     OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_TESTS       OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_INSTALL     OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_BACKEND_STB ON  CACHE BOOL "" FORCE)
set(SDLIMAGE_PNG         ON  CACHE BOOL "" FORCE)
set(SDLIMAGE_PNG_LIBPNG  OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_BMP         ON  CACHE BOOL "" FORCE)
foreach(_off AVIF JPG JXL TIF WEBP GIF)
    set(SDLIMAGE_${_off} OFF CACHE BOOL "" FORCE)
endforeach()
FetchContent_Declare(SDL3_image
    URL "https://github.com/libsdl-org/SDL_image/releases/download/release-${SDL3_IMG_VER}/SDL3_image-${SDL3_IMG_VER}.tar.gz")

# SDL first: SDL_mixer and SDL_image use the in-tree SDL3::SDL3-shared target
# when it exists instead of searching for an installed SDL3.
FetchContent_MakeAvailable(SDL3)
FetchContent_MakeAvailable(SDL3_mixer SDL3_image)

add_library(kfx_sdl3 INTERFACE)
target_link_libraries(kfx_sdl3 INTERFACE SDL3::SDL3 SDL3_mixer::SDL3_mixer SDL3_image::SDL3_image)

# --- vcpkg libraries (x64-uwp-static-md) ---------------------------------------
find_package(ZLIB REQUIRED)
find_package(minizip CONFIG REQUIRED)
find_package(SPNG CONFIG REQUIRED)
find_package(OpenAL CONFIG REQUIRED)
find_package(CURL REQUIRED)
find_package(FFMPEG REQUIRED)

add_library(kfx_ffmpeg INTERFACE)
target_include_directories(kfx_ffmpeg INTERFACE ${FFMPEG_INCLUDE_DIRS})
target_link_directories(kfx_ffmpeg INTERFACE ${FFMPEG_LIBRARY_DIRS})
target_link_libraries(kfx_ffmpeg INTERFACE ${FFMPEG_LIBRARIES})

# --- LuaJIT (built by build/uwp/build-luajit.ps1) -----------------------------
set(KFX_LUAJIT_DIR "" CACHE PATH "Output folder of build/uwp/build-luajit.ps1 (contains include/ and lib/lua51.lib)")
if(NOT KFX_LUAJIT_DIR OR NOT EXISTS "${KFX_LUAJIT_DIR}/lib/lua51.lib")
    message(FATAL_ERROR "LuaJIT for UWP not found. Run build/uwp/build-luajit.ps1 and pass -DKFX_LUAJIT_DIR=<its output folder>.")
endif()
add_library(luajit_static STATIC IMPORTED GLOBAL)
set_target_properties(luajit_static PROPERTIES
    IMPORTED_LOCATION "${KFX_LUAJIT_DIR}/lib/lua51.lib"
    INTERFACE_INCLUDE_DIRECTORIES "${KFX_LUAJIT_DIR}/include")

# --- enet6 ---------------------------------------------------------------------
FetchContent_Declare(enet6
    GIT_REPOSITORY https://github.com/SirLynix/enet6.git
    GIT_TAG        v6.1.3
    PATCH_COMMAND  git apply --ignore-whitespace "${KFX_UWP_PATCHES}/enet6-uwp.patch"
    UPDATE_DISCONNECTED TRUE)
set(BUILD_SHARED_LIBS OFF)
FetchContent_MakeAvailable(enet6)
target_compile_definitions(enet6 PRIVATE WINAPI_FAMILY=WINAPI_FAMILY_APP)

# --- centijson + centitoml -----------------------------------------------------
FetchContent_Declare(centijson
    GIT_REPOSITORY https://github.com/mity/centijson.git
    GIT_TAG        8c7a5fb42d9f55044d60592809288164adb4ca95)
FetchContent_GetProperties(centijson)
if(NOT centijson_POPULATED)
    FetchContent_Populate(centijson)
endif()
add_library(centijson_static STATIC
    "${centijson_SOURCE_DIR}/src/json.c"
    "${centijson_SOURCE_DIR}/src/json-dom.c"
    "${centijson_SOURCE_DIR}/src/json-ptr.c"
    "${centijson_SOURCE_DIR}/src/value.c")
target_include_directories(centijson_static PUBLIC "${centijson_SOURCE_DIR}/src")
target_compile_definitions(centijson_static PRIVATE _CRT_SECURE_NO_WARNINGS)

add_library(centitoml OBJECT "${KFX_CENTITOML_SRC}/toml_api.c")
target_link_libraries(centitoml PUBLIC centijson_static)
target_include_directories(centitoml INTERFACE "${KFX_CENTITOML_SRC}")

# --- astronomy -----------------------------------------------------------------
FetchContent_Declare(astronomy
    GIT_REPOSITORY https://github.com/cosinekitty/astronomy.git
    GIT_TAG        865d3da7d8112bbc7911238052c6af4aaf877181
    GIT_SHALLOW    FALSE)
FetchContent_GetProperties(astronomy)
if(NOT astronomy_POPULATED)
    FetchContent_Populate(astronomy)
endif()
add_library(astronomy_static STATIC "${astronomy_SOURCE_DIR}/source/c/astronomy.c")
target_include_directories(astronomy_static PUBLIC "${astronomy_SOURCE_DIR}/source/c")
target_compile_definitions(astronomy_static PRIVATE _CRT_SECURE_NO_WARNINGS _USE_MATH_DEFINES)

# --- OpenGL loader -------------------------------------------------------------
# The GL renderer is still compiled (RendererManager and the window system
# reference it) but never selected on UWP; glad resolves GL through
# SDL_GL_GetProcAddress, so nothing links against opengl32.
add_library(glad STATIC "${CMAKE_SOURCE_DIR}/deps/glad/src/glad.c")
target_include_directories(glad PUBLIC "${CMAKE_SOURCE_DIR}/deps/glad/include")

# Link every dependency onto TARGET.
function(kfx_link_dependencies TARGET)
    target_link_libraries(${TARGET} PRIVATE
        kfx_sdl3
        kfx_ffmpeg
        OpenAL::OpenAL
        CURL::libcurl
        $<IF:$<TARGET_EXISTS:spng::spng>,spng::spng,spng::spng_static>
        $<IF:$<TARGET_EXISTS:MINIZIP::minizip>,MINIZIP::minizip,MINIZIP::minizipstatic>
        ZLIB::ZLIB
        luajit_static
        enet6
        astronomy_static
        centijson_static
        centitoml
        glad)
    # Static openal-soft: don't mark its functions dllimport.
    target_compile_definitions(${TARGET} PRIVATE AL_LIBTYPE_STATIC CURL_STATICLIB)
endfunction()
