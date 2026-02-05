#include "custombackend.h"
#include <QDir>
#include <QProcess>

bool CustomBackend::isAvailable() const {
    // Custom backend is always available -- users can always add games manually
    return true;
}

QVector<Game> CustomBackend::scanLibrary() {
    // Custom games are already in the database; no external source to scan.
    // They are added via the Luna UI "Add Non-Store Game" flow.
    return {};
}

bool CustomBackend::launchGame(const Game& game) {
    if (game.launchCommand.isEmpty() && game.executablePath.isEmpty()) {
        return false;
    }

    if (!game.launchCommand.isEmpty()) {
        // Launch via shell command
        return QProcess::startDetached("/bin/sh", QStringList() << "-c" << game.launchCommand);
    }

    // Launch executable directly
    return QProcess::startDetached(game.executablePath);
}
