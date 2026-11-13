# KeeperFX on Xbox (UWP, Developer Mode)

This branch builds KeeperFX as a UWP app package that runs on Xbox One and
Xbox Series consoles in **Developer Mode**, and on Windows 10/11 as a sideloaded
Store-style app. It is not a retail Xbox release: the game needs the original
Dungeon Keeper files, so it can't go through the Microsoft Store.

> Status: **untested prototype.** The UWP code paths have been checked against
> the UWP API family (no desktop-only Win32 calls), but the project has not been
> built with Visual Studio or run on a console yet. Expect the first build to
> need small fixes; see "Known gaps" at the end.

## What you need

- A Windows 10/11 PC with **Visual Studio 2022** and these workloads:
  *Desktop development with C++* and *Universal Windows Platform development*
  (include the *C++ (v143) Universal Windows Platform tools* component).
- **CMake 3.25+** and **git** on `PATH`.
- **vcpkg** cloned somewhere, with `VCPKG_ROOT` set to that folder.
- An Xbox in Developer Mode (the *Xbox Dev Mode* app from the Store, plus a
  Microsoft Partner Center developer account).
- Your Dungeon Keeper files (GOG, Steam, Origin or CD) and a KeeperFX release
  (for the `data`, `campgns`, `levels`, `fxdata` etc. folders).

## 1. Build LuaJIT for UWP

vcpkg's LuaJIT doesn't support UWP, so build it once with the script in this
folder. It clones LuaJIT at a pinned commit and builds an interpreter-only
static library (no JIT, which UWP would only allow with an extra capability).

```powershell
powershell -ExecutionPolicy Bypass -File build\uwp\build-luajit.ps1
```

Output goes to `out\luajit-uwp`, which the `uwp-x64` preset already points at.

## 2. Configure and build

```powershell
cmake --preset uwp-x64
cmake --build --preset uwp-x64-release
```

The first configure takes a while: vcpkg builds zlib, minizip, libspng,
openal-soft, curl and FFmpeg for the `x64-uwp-static-md` triplet, and CMake
fetches SDL3 (the [SternXD/SDL3-uwp](https://github.com/SternXD/SDL3-uwp) fork,
because upstream SDL3 no longer has a UWP backend), SDL3_mixer, SDL3_image,
enet6, centijson and astronomy.

You can also open `out\build\uwp-x64\keeperfx.sln` in Visual Studio and build
or deploy from there.

### Signing certificate

UWP packages must be signed. In Visual Studio, open
`out\build\uwp-x64\uwp\Package.appxmanifest` (it's in the `keeperfx` project),
go to **Packaging > Choose Certificate > Create test certificate**. If the
certificate's subject isn't `CN=KeeperFX`, reconfigure with
`-DKFX_UWP_PUBLISHER="CN=<your subject>"` so the generated manifest keeps
matching it.

## 3. Deploy to the Xbox

Either:

- **From Visual Studio:** set the platform to *x64*, the target to *Remote
  Machine*, enter the console's IP (shown in Dev Home), and press F5 or use
  *Deploy*. Pair with the PIN from Dev Home the first time.
- **From the Device Portal:** in Visual Studio use *Project > Publish > Create
  App Packages* (sideloading), then open the Device Portal
  (`https://<xbox-ip>:11443`) and install the `.msix`/`.appx` under
  *My games & apps > Add*.

Then, in Dev Home, select KeeperFX, press the menu button, choose
**View details** and set **App type: Game**. UWP *apps* on Xbox are limited to
about 1 GB of memory and share the GPU; *games* get the full allowance.

## 4. Copy the game files onto the console

The game runs from its own **LocalState\KeeperFX** folder (it's created on first
launch; the game shows a message with the full path if the files aren't there).

1. Launch KeeperFX once and close it, so the folder exists.
2. Open the Device Portal, go to **File explorer > LocalAppData >
   KeeperFX.DungeonKeeper_… > LocalState > KeeperFX**.
3. Upload a complete, working KeeperFX installation into that folder: the
   KeeperFX release files *and* the Dungeon Keeper files merged into it, exactly
   as they are after running the KeeperFX launcher on a PC. The easiest way is
   to set KeeperFX up on a PC first and upload that folder's contents.
   `keeperfx.cfg` must end up directly in `LocalState\KeeperFX`.

The Device Portal uploads one folder level at a time, so this takes a few
rounds. Saves, settings (`keeperfx.cfg`, `renderer_prefs.ini`) and
`keeperfx.log` live in the same folder, so you can fetch the log from there if
something goes wrong.

### Command-line options

A console has no command line. Put options in `commandline.txt` in the same
folder, separated by spaces, e.g.:

```
-nointro -alex
```

## Playing with a controller

KeeperFX already supports gamepads: a stick moves the cursor, and every game
action can be bound to a controller button in the in-game controls menu (saved
to `save\settings.toml`). A USB mouse and keyboard also work on Xbox.

## What's different from the PC build

| Area | UWP behaviour | Where |
|---|---|---|
| Entry point, game folder | `SDL_main` via SDL's WinRT `WinMain`; runs in `LocalState\KeeperFX`; arguments from `commandline.txt` | `src/kfx/platform/PlatformUWP.cpp` |
| Renderer | Software renderer only (presented through SDL's Direct3D 11 renderer); the OpenGL renderer is compiled but never selected | `src/kfx/renderer/RendererManager.cpp` |
| CD audio, Steam | Not available; music plays from the ogg files | `PlatformUWP.cpp` |
| Crash handler | C signal handlers only (no dbghelp stack walk or minidump) | `src/bflib_crash.c` |
| Replay rewind memory tracker | Off (reports "not available"; rewind falls back to its slower path) | `src/kernel_memtracker.c` |
| UPnP / NAT-PMP port mapping | Off (multiplayer hosts must forward ports themselves) | `src/net_portforward.cpp` |
| TLS for matchmaking | curl uses OpenSSL with `cacert.pem` (downloaded from curl.se at configure time) shipped in the package | `src/net_matchmaking.c`, `BuildTargets.cmake` |
| Suspend / resume | Treated like losing / regaining window focus (music paused, audio muted per settings) | `src/bflib_inputctrl.cpp` |
| Back / B button | Marked handled, so it reaches the game instead of leaving the app | `PlatformUWP.cpp` |
| Dependencies | SDL3 from the UWP fork, vcpkg `x64-uwp-static-md`, LuaJIT from `build-luajit.ps1`, enet6 with a small UWP patch | `build/cmake/modules/DependenciesUWP.cmake`, `build/uwp/` |

Desktop builds (MinGW, Linux) are unchanged: everything UWP-specific is behind
`KFX_UWP`, which CMake only sets for `CMAKE_SYSTEM_NAME=WindowsStore`.

## Known gaps

- **Not built with MSVC yet.** KeeperFX's main toolchains are MinGW and GCC.
  There is an MSVC preset and a `compiler_compat.h`, but expect a few MSVC
  compile errors on the first build (GCC-only syntax, warnings-as-errors in
  dependencies). The UWP-specific code was syntax-checked with clang against
  the UWP API family, not compiled with MSVC.
- **SDL3-uwp is a community fork.** It's pinned to a known commit
  (`KFX_SDL3_UWP_COMMIT` in `DependenciesUWP.cmake`). If its WinRT backend has
  bugs (input, audio, window size), that's where to look first.
- **APPX0702 / missing .winmd:** SDL's `SDL_main.h` skips its C++/CX check when
  compiling as C++20, which KeeperFX does. If Visual Studio still reports a
  missing Windows metadata file, add `SDL_WINRT_METADATA_FILE_AVAILABLE` and
  compile one small source file with `/ZW`.
- **Display size:** UWP gives the game one full-screen window; resolution
  options in the menus may not all apply. The TV-safe area isn't handled.
- **Performance:** the software renderer is CPU-bound. Xbox One should cope at
  low resolutions; Series S/X has plenty of headroom.
