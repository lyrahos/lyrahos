#ifndef LUTRISBACKEND_H
#define LUTRISBACKEND_H

#include "../storebackend.h"

class LutrisBackend : public StoreBackend {
public:
    QString name() const override { return "lutris"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;
};

#endif
