// -----------------------------------------------------------------------------
// QDomyos-Zwift: ANT+ Virtual Footpod Feature
// C++ Singleton for ANT+ Worker Lifecycle Management (Header)
//
// Part of QDomyos-Zwift project: https://github.com/cagnulein/qdomyos-zwift
// Contributor(s): bassai-sho
// AI analysis tools (Claude, Gemini) were used to assist coding and debugging
// Licensed under GPL-3.0 - see project repository for full license
//
// This file declares the AntManager singleton class, which is responsible for
// managing the lifecycle of the ANT+ worker thread.
// -----------------------------------------------------------------------------

#ifndef ANTMANAGER_H
#define ANTMANAGER_H

#include <QObject>
#include "devices/bluetoothdevice.h"

class AntWorker;

class AntManager : public QObject {
    Q_OBJECT
public:
    static AntManager& instance();
    void startForDevice(bluetoothdevice* device);
    void stopForDevice(bluetoothdevice* device);
    static QString validateEnvironment();
    void reparent(QObject* newParent);

private slots:
    void onWorkerFinished();

private:
    AntManager(QObject* parent = nullptr);
    ~AntManager();
    AntManager(const AntManager&) = delete;
    AntManager& operator=(const AntManager&) = delete;

    QThread* m_workerThread = nullptr;
    AntWorker* m_worker = nullptr;
    bluetoothdevice* m_currentDevice = nullptr;
};

#endif // ANTMANAGER_H