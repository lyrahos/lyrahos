#ifndef HEROICBACKEND_H
#define HEROICBACKEND_H

#include "../storebackend.h"

class HeroicBackend : public StoreBackend {
public:
    QString name() const override { return "heroic"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;
};

#endif
