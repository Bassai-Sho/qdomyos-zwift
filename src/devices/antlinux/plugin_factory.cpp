#include "plugin_factory.h"
#include "AntManager.h"
#include <QDebug>

// This file creates a C++ object that is part of a Qt plugin.
// It is the entry point from the main application into the plugin's code.

extern "C" {

QObject* qz_ant_create(QObject* parent)
{
    qInfo() << "[ANT+ Plugin] Factory called. Accessing AntManager singleton instance...";
    
    // Get the one and only instance of the AntManager.
    AntManager& manager = AntManager::instance();
    
    // Set its parent to ensure proper Qt object lifetime management.
    manager.reparent(parent);
    
    // Return a pointer to the existing singleton instance.
    return &manager;
}

} // extern "C"