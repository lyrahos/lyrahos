#ifndef STOREBACKEND_H
#define STOREBACKEND_H

#include <QObject>
#include <QVector>
#include "database.h"

class StoreBackend {
public:
    virtual ~StoreBackend() = default;
    virtual QString name() const = 0;
    virtual QVector<Game> scanLibrary() = 0;
    virtual bool launchGame(const Game& game) = 0;
    virtual bool isAvailable() const = 0;
};

#endif
