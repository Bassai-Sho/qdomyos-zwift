// -----------------------------------------------------------------------------
// QDomyos-Zwift: ANT+ Virtual Footpod Feature
// C++ Singleton for ANT+ Worker Lifecycle Management (Implementation)
//
// Part of QDomyos-Zwift project: https://github.com/cagnulein/qdomyos-zwift
// Contributor(s): bassai-sho
// AI analysis tools (Claude, Gemini) were used to assist coding and debugging
// Licensed under GPL-3.0 - see project repository for full license
//
// This file implements the AntManager singleton. Its responsibility is to create,
// manage, and destroy the AntWorker and its QThread in response to treadmill
// connection and disconnection events, ensuring a clean lifecycle.
// -----------------------------------------------------------------------------

#include "AntManager.h"

#ifdef ANT_LINUX_ENABLED
#include "AntManager.h"
#include "AntWorker.h"
#include "PythonLoader.h"
#include <QThread>
#include <QDebug>
#include <QDir>       // <-- FIX: Added the missing include for QDir
#include <QFile>      // For QFile
#include <QProcess>   // For QProcess
#include <QRegExp>    // For QRegExp
#include <unistd.h>   // For geteuid()
#include <pybind11/embed.h>

QString AntManager::validateEnvironment() {
    // --- This function is now sudo-aware and performs all necessary checks ---

    // Determine the real user and their home directory, even when run with sudo.
    QString targetUser;
    QString targetHomePath;
    const char* sudo_user_cstr = getenv("SUDO_USER");

    if (sudo_user_cstr && strlen(sudo_user_cstr) > 0) {
        targetUser = sudo_user_cstr;
        targetHomePath = QString("/home/%1").arg(targetUser);
    } else {
        // Fallback for non-sudo execution (or if run as root directly)
        targetUser = QDir::home().dirName();
        targetHomePath = QDir::homePath();
    }

    // === Check 1: Python Virtual Environment ===
    QString venv_path = targetHomePath + "/ant_venv";
    if (!QDir(venv_path).exists()) {
        return QString("Python virtual environment not found for user '%1' at '%2'.\n\n"
                       "Please create it by running (without sudo):\n"
                       "  python3.11 -m venv %2\n"
                       "  %2/bin/pip install openant pyusb pybind11").arg(targetUser, venv_path);
    }

    // === Check 2: udev Rules for USB Permissions ===
    // This check is more specific and helpful than just checking group membership.
    if (!QFile::exists("/etc/udev/rules.d/99-ant-usb.rules")) {
        return "ANT+ udev rule file not found at '/etc/udev/rules.d/99-ant-usb.rules'.\n\n"
               "This file is required to grant this application access to the USB dongle.\n"
               "Please create it as per the README instructions.";
    }

    // === Check 3: Group Membership (as required by the udev rule) ===
    bool in_plugdev_group = false;
    QProcess process;
    process.start("groups", QStringList() << targetUser); // Check groups for the target user
    process.waitForFinished();
    QString groups_output = process.readAllStandardOutput();
    
    QRegExp plugdev_re("\\bplugdev\\b");
    if (groups_output.contains(plugdev_re)) {
        in_plugdev_group = true;
    }

    if (!in_plugdev_group) {
        return QString("User '%1' is not a member of the 'plugdev' group, which is required by the udev rule.\n\n"
                       "Please run the following command, then LOG OUT and LOG BACK IN:\n"
                       "  sudo usermod -aG plugdev %1").arg(targetUser);
    }

    // === Check 4: Python Library Availability (Version-Agnostic) ===
    // We use the macros from Python.h (included by pybind11) to get the version
    // this binary was compiled against, making this check robust.
    QString required_python_version = QString("%1.%2").arg(PY_MAJOR_VERSION).arg(PY_MINOR_VERSION);
    try {
        if (!Py_IsInitialized()) {
             // This is just a test to confirm the linked library can be reached.
        }
    } catch (const std::exception& e) {
        return QString("Failed to access the Python library (expected for Python %1).\n\n"
                       "Please ensure Python %1 is installed correctly and its '.so' library is in the system path.\n"
                       "Error: %2").arg(required_python_version, e.what());
    }

    return QString(); // Empty string signifies success
}

AntManager& AntManager::instance() {
    static AntManager manager;
    return manager;
}

// Implement the new public method.
void AntManager::reparent(QObject* newParent) {
    this->setParent(newParent);
}

AntManager::AntManager(QObject* parent) : QObject(parent) {}

// Destructor is now minimal. All cleanup is explicitly handled in stopForDevice.
AntManager::~AntManager() {
    qInfo() << "[ANT+] AntManager destroyed.";
}

void AntManager::startForDevice(bluetoothdevice* device) {
    if (m_workerThread) {
        qWarning("[ANT+] Manager: A worker is already running.");
        return;
    }

    // --- ON-DEMAND INITIALIZATION ---
    // This now happens only when the ANT+ feature is actually used.
    if (!PythonLoader::isInitialized()) {
        if (!PythonLoader::initialize()) {
            qCritical() << "[AntManager] FATAL: Failed to initialize Python runtime. ANT+ feature will be disabled.";
            return; // Abort start
        }
    }
    // --- END ON-DEMAND INITIALIZATION ---

    qInfo() << "[ANT+] Manager: Received start command. Initializing worker thread...";
    m_currentDevice = device;
    
    m_workerThread = new QThread(this);
    m_workerThread->setObjectName("AntWorkerThread");
    m_worker = new AntWorker(m_currentDevice);
    m_worker->moveToThread(m_workerThread);
    
    // This is the correct, thread-safe way to set the thread's priority.
    // It runs in the new thread's context right after it starts.
    connect(m_workerThread, &QThread::started, [this]() {
        qInfo() << "[ANT+] AntWorkerThread has started. Setting to high priority.";
        m_workerThread->setPriority(QThread::TimeCriticalPriority);
    });

    connect(m_workerThread, &QThread::started, m_worker, &AntWorker::start);
    connect(m_worker, &AntWorker::finished, m_workerThread, &QThread::quit);
    connect(m_workerThread, &QThread::finished, this, &AntManager::onWorkerFinished);
    
    // Connect device disconnection to our stop function
    connect(device, &bluetoothdevice::disconnected, this, [this, device](){
        this->stopForDevice(device);
    });

    m_workerThread->start();
}

void AntManager::stopForDevice(bluetoothdevice* device) {
    // Check if there is anything to stop.
    if (!m_workerThread || !m_workerThread->isRunning()) {
        return;
    }

    // If called for a specific device, ensure it's the one we are managing.
    if (device && device != m_currentDevice) {
        return;
    }

    qInfo() << "[ANT+] Manager: Stopping ANT+ worker thread...";

    // 1. Signal the worker (in its own thread) to stop its timers and Python script.
    QMetaObject::invokeMethod(m_worker, "stop", Qt::QueuedConnection);

    // 2. Tell the thread's event loop to exit once the worker's tasks are done.
    m_workerThread->quit();

    // 3. Block this (main) thread and wait for the worker thread to completely finish.
    // This is the most critical step to prevent race conditions.
    if (!m_workerThread->wait(3000)) { // Use a generous 3-second timeout
        qWarning() << "[ANT+] Worker thread did not stop gracefully. Terminating.";
        m_workerThread->terminate();
        m_workerThread->wait(500);
    } else {
        qInfo() << "[ANT+] Worker thread stopped cleanly.";
    }
}

void AntManager::onWorkerFinished() {
    // This slot is now called after the thread's event loop has finished.
    qInfo() << "[ANT+] Worker thread has finished. Cleaning up manager resources.";
    
    if (m_currentDevice) {
        disconnect(m_currentDevice, nullptr, this, nullptr);
    }
    
    if (m_worker) m_worker->deleteLater();
    if (m_workerThread) m_workerThread->deleteLater();
    
    m_worker = nullptr;
    m_workerThread = nullptr;
    m_currentDevice = nullptr;
}

#endif // ANT_LINUX_ENABLED