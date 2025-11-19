# qz_ant_plugin.pro
# ANT+ Plugin Project File - with Intelligent Path Detection & Diagnostics

TEMPLATE = lib
CONFIG += plugin c++17
QT += core bluetooth positioning

TARGET = qz_ant
DESTDIR = ../../  # Output into src/

INCLUDEPATH += . .. ../..

# ============================================================================
# Python Environment Detection (with HEAVY DIAGNOSTICS)
# ============================================================================

message("--- [PLUGIN DIAG] Parsing qz_ant_plugin.pro ---")

# --- Intelligent Path Searching (This part works) ---
SEARCH_PATHS = \
    $$PWD/../../.ant_venv_path \
    $$OUT_PWD/../../.ant_venv_path \
    $$OUT_PWD/.ant_venv_path
VENV_PATH_FILE = ""
for(path, SEARCH_PATHS) {
    if (exists($$path)) {
        VENV_PATH_FILE = $$clean_path($$path)
        break()
    }
}

exists($$VENV_PATH_FILE) {
    message("[DIAG] Found .ant_venv_path at:" $$VENV_PATH_FILE)
 
    # CRITICAL NOTE FOR FUTURE DEVELOPERS:
    # Do NOT use qmake's built-in $$cat() or $$read_file() functions here.
    # Testing has proven they are unreliable inside the Docker/subdirs build
    # context and can return empty strings or cause parser warnings.
    #
    # Using an external 'cat' command via $$system() is the only method
    # that has been proven to work reliably and consistently.
    VENV_PYTHON_FROM_SYSTEM = $$system("cat $$VENV_PATH_FILE")
    message("[DIAG] Content from $$system(cat): '" $$VENV_PYTHON_FROM_SYSTEM "'")

    # We will now use the most reliable method and proceed
    VENV_PYTHON = $$VENV_PYTHON_FROM_SYSTEM

    !exists($$VENV_PYTHON) {
        error("Python executable not found at path read from file: $$VENV_PYTHON")
    }
    message("[DIAG] Final selected Python executable:" $$VENV_PYTHON)
    
    # ... (The rest of your .pro file remains the same) ...
    HELPER_SCRIPT = $$PWD/check_ant_env.sh
    # ...
    
} else {
    error("ANT+ plugin requires .ant_venv_path. Searched: $$SEARCH_PATHS")
}

# ============================================================================
# Source Files
# ============================================================================
SOURCES += AntManager.cpp AntWorker.cpp PythonLoader.cpp plugin_factory.cpp
HEADERS += AntManager.h AntWorker.h PythonLoader.h plugin_factory.h