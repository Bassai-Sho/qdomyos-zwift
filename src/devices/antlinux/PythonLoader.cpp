// -----------------------------------------------------------------------------
// QDomyos-Zwift: ANT+ Virtual Footpod Feature
// C++ Runtime Loader for the Python Shared Library (Implementation)
//
// Part of QDomyos-Zwift project: https://github.com/cagnulein/qdomyos-zwift
// Contributor(s): bassai-sho
// AI analysis tools (Claude, Gemini) were used to assist coding and debugging
// Licensed under GPL-3.0 - see project repository for full license
//
// This file implements the PythonLoader class. It uses the Python version
// detected at build time to robustly locate and dlopen the correct libpython
// shared object at runtime. All diagnostic output is channeled through Qt's
// logging system (qInfo/qWarning).
// -----------------------------------------------------------------------------

#include "PythonLoader.h"

#include <dlfcn.h>
#include <string>
#include <vector>
#include <filesystem>
#include <QDebug>

namespace fs = std::filesystem;

// Helper macros to turn the build-time preprocessor defines into C++ strings
#define STRINGIFY(x) #x
#define TOSTRING(x) STRINGIFY(x)

static void *py_handle = nullptr;
static bool py_initialized = false;

typedef void (*PyInitFunc)(void);
typedef int  (*PyFinalizeExFunc)(void);

static bool try_dlopen(const std::string &path) {
    if (py_handle) return true;
    
    dlerror(); // Clear any previous dlerror() state
    void *h = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
    const char *err = dlerror();

    if (h) {
        py_handle = h;
        qInfo().noquote() << "[PythonLoader] dlopen succeeded for:" << QString::fromStdString(path);
        return true;
    } else if (err) {
        qDebug().noquote() << "[PythonLoader] dlopen attempt failed for" << QString::fromStdString(path) << ":" << err;
    }
    return false;
}

bool PythonLoader::load(const std::string &soname) {
    if (py_handle) return true;

    // Use the version numbers passed in as DEFINES from the .pri file.
    const std::string major_ver = TOSTRING(PY_BUILD_MAJOR_VER);
    const std::string minor_ver = TOSTRING(PY_BUILD_MINOR_VER);
    const std::string required_soname_specific = "libpython" + major_ver + "." + minor_ver + ".so.1.0";
    const std::string required_soname_generic = "libpython" + major_ver + "." + minor_ver + ".so";

    // Priority 1: Try the most specific library name first via the system linker.
    if (try_dlopen(required_soname_specific)) {
        return true;
    }

    // Priority 2: Try a more generic name as a fallback.
    if (try_dlopen(required_soname_generic)) {
        return true;
    }

    qWarning().noquote() << "[PythonLoader] ERROR: Failed to locate and load the required Python library.";
    qWarning().noquote() << "[PythonLoader] Searched for" << QString::fromStdString(required_soname_specific)
                         << "and" << QString::fromStdString(required_soname_generic);
    qWarning().noquote() << "[PythonLoader] Please ensure Python" << QString::fromStdString(major_ver) << "." << QString::fromStdString(minor_ver)
                         << "is installed and its library is in the system's search path (ldconfig).";
    return false;
}

bool PythonLoader::initialize() {
    if (py_initialized) return true;
    if (!isLoaded() && !load()) return false;

    dlerror(); // Clear any existing errors
    void *sym = dlsym(py_handle, "Py_Initialize");
    const char *err = dlerror();
    if (err || !sym) {
        qWarning().noquote() << "[PythonLoader] ERROR: dlsym(Py_Initialize) failed:" << (err ? err : "symbol not found");
        return false;
    }

    auto pyInit = reinterpret_cast<PyInitFunc>(sym);
    pyInit();
    py_initialized = true;
    qInfo() << "[PythonLoader] Py_Initialize() called successfully.";
    return true;
}

void PythonLoader::finalize() {
    if (!py_initialized) return;

    dlerror();
    void *sym = dlsym(py_handle, "Py_FinalizeEx");
    if (sym) {
        reinterpret_cast<PyFinalizeExFunc>(sym)();
    }
    py_initialized = false;
    
    if (py_handle) {
        dlclose(py_handle);
        py_handle = nullptr;
    }
    qInfo() << "[PythonLoader] Python finalized and handle closed.";
}

bool PythonLoader::isLoaded() { return py_handle != nullptr; }
bool PythonLoader::isInitialized() { return py_initialized; }