# antlinux.pri - Only sets a define.
VENV_PATH_FILE = $$clean_path($$PWD/../../.ant_venv_path)
exists($$VENV_PATH_FILE) {
    DEFINES += ANT_LINUX_ENABLED
}