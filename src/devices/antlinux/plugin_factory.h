#ifndef QZ_ANT_PLUGIN_FACTORY_H
#define QZ_ANT_PLUGIN_FACTORY_H

#include <QObject>

extern "C" {
    Q_DECL_EXPORT QObject* qz_ant_create(QObject* parent);
}

#endif