// -----------------------------------------------------------------------------
// QDomyos-Zwift: ANT+ Virtual Footpod Feature
// C++ Runtime Loader for the Python Shared Library (Header)
//
// Part of QDomyos-Zwift project: https://github.com/cagnulein/qdomyos-zwift
// Contributor(s): bassai-sho
// AI analysis tools (Claude, Gemini) were used to assist coding and debugging
// Licensed under GPL-3.0 - see project repository for full license
//
// This file declares the PythonLoader class, a static utility responsible for
// dynamically loading libpython at runtime. This prevents static linkage,
// resolving a startup deadlock when the application is launched with sudo.
// -----------------------------------------------------------------------------

#pragma once
#include <string>

class PythonLoader {
public:
    static bool initialize();
    static void finalize();
    static bool isInitialized();

private:
    PythonLoader() = default;
    static bool load(const std::string &soname = "");
    static bool isLoaded();
};