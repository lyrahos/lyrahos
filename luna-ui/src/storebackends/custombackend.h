#ifndef CUSTOMBACKEND_H
#define CUSTOMBACKEND_H

#include "../storebackend.h"

// CustomBackend handles user-added standalone games that aren't
// from any specific store. Users add these via "Add Non-Store Game".

class CustomBackend : public StoreBackend {
public:
    QString name() const override { return "custom"; }
    QVector<Game> scanLibrary() override;
    bool launchGame(const Game& game) override;
    bool isAvailable() const override;
};

#endif
