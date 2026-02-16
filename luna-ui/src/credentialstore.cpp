#include "credentialstore.h"
#include <QCryptographicHash>
#include <QFile>
#include <QDir>
#include <QRandomGenerator>

QByteArray CredentialStore::deriveKey()
{
    // Read machine-id as base key material.
    // On Linux this is a unique, persistent, hex string per installation.
    QFile machineId("/etc/machine-id");
    QByteArray keyMaterial;
    if (machineId.open(QIODevice::ReadOnly)) {
        keyMaterial = machineId.readAll().trimmed();
    } else {
        // Fallback: use hostname + home dir as entropy source.
        // Less unique but still machine-specific.
        keyMaterial = QDir::homePath().toUtf8() + QByteArray("luna-ui-fallback");
    }

    // Derive 256-bit key using SHA-256 with app-specific salt
    QByteArray salted = QByteArray("luna-ui-credential-store-v1:") + keyMaterial;
    return QCryptographicHash::hash(salted, QCryptographicHash::Sha256);
}

QByteArray CredentialStore::generateNonce()
{
    QByteArray nonce(16, '\0');
    QRandomGenerator *rng = QRandomGenerator::system();
    for (int i = 0; i < 16; i++)
        nonce[i] = static_cast<char>(rng->bounded(256));
    return nonce;
}

QByteArray CredentialStore::encrypt(const QByteArray& plaintext)
{
    if (plaintext.isEmpty())
        return QByteArray();

    QByteArray key = deriveKey();
    QByteArray nonce = generateNonce();

    // SHA-256 counter-mode stream cipher:
    // keystream_block[i] = SHA-256(key || nonce || counter_bytes)
    // ciphertext = plaintext XOR keystream
    QByteArray ciphertext;
    ciphertext.reserve(plaintext.size());
    int offset = 0;
    int counter = 0;

    while (offset < plaintext.size()) {
        QByteArray counterBytes = QByteArray::number(counter);
        QByteArray block = QCryptographicHash::hash(
            key + nonce + counterBytes, QCryptographicHash::Sha256);

        int remaining = plaintext.size() - offset;
        int blockLen = qMin(remaining, 32);

        for (int i = 0; i < blockLen; i++)
            ciphertext.append(static_cast<char>(plaintext[offset + i] ^ block[i]));

        offset += blockLen;
        counter++;
    }

    // Output format: [16-byte nonce][ciphertext]
    return nonce + ciphertext;
}

QByteArray CredentialStore::decrypt(const QByteArray& data)
{
    // Minimum size: 16 (nonce) + 1 (at least one byte of ciphertext)
    if (data.size() <= 16)
        return QByteArray();

    QByteArray key = deriveKey();
    QByteArray nonce = data.left(16);
    QByteArray ciphertext = data.mid(16);

    // XOR is its own inverse — same keystream generation as encrypt
    QByteArray plaintext;
    plaintext.reserve(ciphertext.size());
    int offset = 0;
    int counter = 0;

    while (offset < ciphertext.size()) {
        QByteArray counterBytes = QByteArray::number(counter);
        QByteArray block = QCryptographicHash::hash(
            key + nonce + counterBytes, QCryptographicHash::Sha256);

        int remaining = ciphertext.size() - offset;
        int blockLen = qMin(remaining, 32);

        for (int i = 0; i < blockLen; i++)
            plaintext.append(static_cast<char>(ciphertext[offset + i] ^ block[i]));

        offset += blockLen;
        counter++;
    }

    return plaintext;
}

bool CredentialStore::saveEncrypted(const QString& filePath, const QByteArray& data)
{
    // Ensure parent directory exists
    QFileInfo fi(filePath);
    QDir().mkpath(fi.absolutePath());

    QByteArray encrypted = encrypt(data);
    if (encrypted.isEmpty())
        return false;

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly))
        return false;

    // Set restrictive permissions (owner read/write only)
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    file.write(encrypted);
    return true;
}

QByteArray CredentialStore::loadEncrypted(const QString& filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return QByteArray();

    return decrypt(file.readAll());
}
