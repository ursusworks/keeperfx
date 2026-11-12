#ifndef PLATFORM_UWP_H
#define PLATFORM_UWP_H

#include "kfx/platform/IPlatform.h"

/** Universal Windows Platform (Windows 10/11 Store apps and Xbox One /
 *  Series consoles in Developer Mode).
 *
 *  UWP apps run in an AppContainer sandbox: no registry, no CD drives, no
 *  Steam, no dbghelp, and only the app's own folders are writable. The game
 *  runs from the app's LocalState folder (see PlatformUWP.cpp), which is
 *  where the original Dungeon Keeper files and the KeeperFX data go. */
class PlatformUWP : public IPlatform {
public:
    const char* GetOSVersion() const override;
    const void* GetImageBase() const override;
    const char* GetWineVersion() const override;
    const char* GetWineHost() const override;

    TbFileFind* FileFindFirst(const char* filespec, TbFileEntry* entry) override;

    const char* GetUserPrefDir() override;

    void   SetRedbookVolume(SoundVolume vol) override;
    TbBool PlayRedbookTrack(int track) override;
    void   PauseRedbookTrack() override;
    void   ResumeRedbookTrack() override;
    void   StopRedbookTrack() override;

    int  InitSteam() override;
    void ShutdownSteam() override;

    bool VideoInit() override;

    // A UWP app gets one CoreWindow that covers the screen; there is no
    // display-mode switching to probe.
    bool OwnsDisplay() const override { return true; }
    bool ForcesAllModesAvailable() const override { return true; }
};

/** Absolute UTF-8 path of the folder the game runs from (no trailing
 *  separator). Valid after the process entry point has run. */
const char* PlatformUWP_GetGameDir();

#endif // PLATFORM_UWP_H
