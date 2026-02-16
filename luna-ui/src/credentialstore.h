#ifndef CREDENTIALSTORE_H
#define CREDENTIALSTORE_H

#include <QByteArray>
#include <QString>

// Encrypts and decrypts credential data using a machine-specific key
// derived from /etc/machine-id via SHA-256.
//
// Format on disk: [16-byte random nonce] + [ciphertext]
// Cipher: SHA-256 counter-mode stream cipher (XOR with SHA-256 keystream)
//
// This binds credentials to the specific machine — copying the encrypted
// file to another device will not allow decryption.

class CredentialStore {
public:
    static QByteArray encrypt(const QByteArray& plaintext);
    static QByteArray decrypt(const QByteArray& ciphertext);

    static bool saveEncrypted(const QString& filePath, const QByteArray& data);
    static QByteArray loadEncrypted(const QString& filePath);

private:
    static QByteArray deriveKey();
    static QByteArray generateNonce();
};

#endif
