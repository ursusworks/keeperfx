/******************************************************************************/
// Free implementation of Bullfrog's Dungeon Keeper strategy game.
/******************************************************************************/
/** @file PlatformUWP.cpp
 *     Universal Windows Platform backend (Xbox One / Series Developer Mode,
 *     and Windows 10/11 as a packaged Store app).
 * @par Purpose:
 *     Process entry point, game folder setup and the per-OS IPlatform services
 *     for a sandboxed UWP app. Built only when KFX_UWP is defined (CMake sets
 *     it for CMAKE_SYSTEM_NAME=WindowsStore).
 * @par  Copying and copyrights:
 *     This program is free software; you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation; either version 2 of the License, or
 *     (at your option) any later version.
 */
/******************************************************************************/
#include "pre_inc.h"
// Only part of UWP builds; empty elsewhere so source globs can include it.
#if defined(KFX_UWP)
#include "kfx/platform/PlatformUWP.h"
#include "kfx/platform/FileFind.h"
#include "platform.h" // kfxmain
#include "bflib_fileio.h"
#include "config.h" // keeper_runtime_directory
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h> // WinRT entry point; renames main() below to SDL_main()
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>
#include "post_inc.h"

#if !defined(SDL_PLATFORM_WINRT)
#error PlatformUWP.cpp needs an SDL3 build with the WinRT/UWP backend (see docs/xbox-uwp.md)
#endif

// Provided by the MSVC linker for every image; replaces GetModuleHandle(NULL),
// which UWP only exposes from Windows 10 1903 on.
extern "C" IMAGE_DOS_HEADER __ImageBase;

namespace {

// Folder the game runs from: <LocalState>\KeeperFX. Writable, survives app
// updates, and reachable from the Xbox Device Portal's file explorer, which is
// how the game files get onto the console.
char g_game_dir[MAX_PATH * 3] = {};

std::wstring utf8_to_wide(const char* s)
{
    if (s == nullptr || *s == '\0')
        return std::wstring();
    const int len = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
    if (len <= 0)
        return std::wstring();
    std::wstring out((size_t)len, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s, -1, &out[0], len);
    out.resize((size_t)len - 1); // drop the terminator MultiByteToWideChar counted
    return out;
}

std::string wide_to_utf8(const wchar_t* s)
{
    if (s == nullptr || *s == L'\0')
        return std::string();
    const int len = WideCharToMultiByte(CP_UTF8, 0, s, -1, nullptr, 0, nullptr, nullptr);
    if (len <= 0)
        return std::string();
    std::string out((size_t)len, '\0');
    WideCharToMultiByte(CP_UTF8, 0, s, -1, &out[0], len, nullptr, nullptr);
    out.resize((size_t)len - 1);
    return out;
}

bool file_exists(const std::string& path)
{
    WIN32_FILE_ATTRIBUTE_DATA data;
    return GetFileAttributesExW(utf8_to_wide(path.c_str()).c_str(), GetFileExInfoStandard, &data) != 0
        && (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

/** Resolve <LocalState>\KeeperFX, create it if needed and make it the
 *  current directory: the engine opens every data file relative to ".". */
bool enter_game_dir()
{
    const char* local = SDL_GetWinRTFSPath(SDL_WINRT_PATH_LOCAL_FOLDER);
    if (local == nullptr)
        return false;
    snprintf(g_game_dir, sizeof(g_game_dir), "%s\\KeeperFX", local);
    const std::wstring wdir = utf8_to_wide(g_game_dir);
    if (!CreateDirectoryW(wdir.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS)
        return false;
    return SetCurrentDirectoryW(wdir.c_str()) != 0;
}

/** There is no command line on a console. Arguments can be put in
 *  commandline.txt next to keeperfx.cfg instead: whitespace-separated, with
 *  double quotes for arguments that contain spaces. */
std::vector<std::string> read_command_line_file()
{
    std::vector<std::string> args;
    FILE* f = fopen("commandline.txt", "rb");
    if (f == nullptr)
        return args;
    std::string text;
    char buf[1024];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0)
        text.append(buf, n);
    fclose(f);

    std::string cur;
    bool in_quotes = false;
    bool have_token = false;
    for (char c : text)
    {
        if (c == '"') {
            in_quotes = !in_quotes;
            have_token = true;
        } else if (!in_quotes && (c == ' ' || c == '\t' || c == '\r' || c == '\n')) {
            if (have_token) {
                args.push_back(cur);
                cur.clear();
                have_token = false;
            }
        } else {
            cur.push_back(c);
            have_token = true;
        }
    }
    if (have_token)
        args.push_back(cur);
    return args;
}

/** Case-insensitive match supporting '*' and '?', as FindFirstFile does. */
bool wildcard_match(const char* pat, const char* str)
{
    const char* star = nullptr;
    const char* resume = nullptr;
    while (*str != '\0')
    {
        if (*pat == '*') {
            star = pat++;
            resume = str;
        } else if (*pat == '?' || tolower((unsigned char)*pat) == tolower((unsigned char)*str)) {
            pat++;
            str++;
        } else if (star != nullptr) {
            pat = star + 1;
            str = ++resume;
        } else {
            return false;
        }
    }
    while (*pat == '*')
        pat++;
    return *pat == '\0';
}

} // namespace

const char* PlatformUWP_GetGameDir()
{
    return g_game_dir;
}

/******************************************************************************/

const char* PlatformUWP::GetOSVersion() const
{
    switch (SDL_GetWinRTDeviceFamily())
    {
        case SDL_WINRT_DEVICEFAMILY_XBOX:    return "Xbox (UWP)";
        case SDL_WINRT_DEVICEFAMILY_DESKTOP: return "Windows (UWP)";
        default:                             return "UWP";
    }
}

const void* PlatformUWP::GetImageBase() const { return &__ImageBase; }
const char* PlatformUWP::GetWineVersion() const { return nullptr; }
const char* PlatformUWP::GetWineHost() const { return nullptr; }

const char* PlatformUWP::GetUserPrefDir()
{
    // Keep renderer_prefs.ini and friends next to the game, where the player
    // can find them through the Device Portal, rather than in SDL's nested
    // <LocalState>\keeperfx\keeperfx.
    static char pref_path[sizeof(g_game_dir)] = {};
    if (pref_path[0] == '\0')
        snprintf(pref_path, sizeof(pref_path), "%s", (g_game_dir[0] != '\0') ? g_game_dir : keeper_runtime_directory);
    return pref_path;
}

TbFileFind* PlatformUWP::FileFindFirst(const char* filespec, TbFileEntry* entry)
{
    try {
        auto ffind = std::make_unique<TbFileFind>();
        // FindFirstFileExW does the matching against the directory listing; the
        // wildcard check below only guards against its 8.3 short-name matches.
        const char* base = std::max(strrchr(filespec, '/'), strrchr(filespec, '\\'));
        const char* name_pattern = (base != nullptr) ? base + 1 : filespec;
        WIN32_FIND_DATAW fd;
        HANDLE handle = FindFirstFileExW(utf8_to_wide(filespec).c_str(), FindExInfoBasic, &fd,
            FindExSearchNameMatch, nullptr, 0);
        if (handle == INVALID_HANDLE_VALUE)
            return nullptr;
        do {
            // Regular files only, matching PlatformWindows / PlatformLinux.
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                continue;
            std::string name = wide_to_utf8(fd.cFileName);
            if (!wildcard_match(name_pattern, name.c_str()))
                continue;
            std::string key = name;
            for (size_t i = 0; i < key.size(); i++)
                key[i] = (char)tolower((unsigned char)key[i]);
            ffind->names.emplace_back(key, name);
        } while (FindNextFileW(handle, &fd));
        FindClose(handle);
        if (ffind->names.empty())
            return nullptr;
        std::sort(ffind->names.begin(), ffind->names.end());
        entry->Filename = ffind->names[0].second.c_str();
        return ffind.release();
    } catch (...) {}
    return nullptr;
}

bool PlatformUWP::VideoInit()
{
    // Mark the Xbox B button / system Back as handled, so it reaches the game
    // as a gamepad button instead of navigating away from the app.
    SDL_SetHint(SDL_HINT_WINRT_HANDLE_BACK_BUTTON, "1");
    if (!SDL_Init(SDL_INIT_VIDEO))
        return false;
    atexit(SDL_Quit);
    return true;
}

// No CD drive access from the sandbox; music comes from the ogg files.
void   PlatformUWP::SetRedbookVolume(SoundVolume) {}
TbBool PlatformUWP::PlayRedbookTrack(int) { return false; }
void   PlatformUWP::PauseRedbookTrack() {}
void   PlatformUWP::ResumeRedbookTrack() {}
void   PlatformUWP::StopRedbookTrack() {}

int  PlatformUWP::InitSteam() { return -1; }
void PlatformUWP::ShutdownSteam() {}

/******************************************************************************/
// Process entry point. SDL_main.h supplies WinMain, which starts the WinRT
// CoreApplication and calls this (renamed to SDL_main) once the window exists.
// argc/argv are empty there, so they are rebuilt from commandline.txt.

int main(int, char*[])
{
    if (!enter_game_dir())
    {
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "KeeperFX",
            "Could not create or enter the game folder in the app's LocalState.", nullptr);
        return 1;
    }
    if (!file_exists("keeperfx.cfg"))
    {
        char msg[sizeof(g_game_dir) + 512];
        snprintf(msg, sizeof(msg),
            "The game files were not found.\n\n"
            "Copy the KeeperFX release files and your original Dungeon Keeper files into:\n\n%s\n\n"
            "On Xbox, use the Device Portal's File explorer (LocalAppData > this app > LocalState > KeeperFX).",
            g_game_dir);
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "KeeperFX", msg, nullptr);
        return 1;
    }

    std::vector<std::string> args = read_command_line_file();
    args.insert(args.begin(), "keeperfx.exe");
    std::vector<char*> argv;
    for (auto& a : args)
        argv.push_back(&a[0]);
    argv.push_back(nullptr);
    return kfxmain((int)args.size(), argv.data());
}

#endif // KFX_UWP
