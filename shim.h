#ifndef OPENSSL_SHIM
#define OPENSSL_SHIM

#import <openssl/ssl.h>

/// A swift-compatible wrapper for BIO_ctrl. The only difference is a type change for the value which allows you to
/// pass a Swift string directly to the function.
static inline int Swift_BIO_ctrl(BIO *bio, int cmd, int larg, const char *value) {
    return BIO_ctrl(bio, cmd, larg, (char *)value);
}

#endif