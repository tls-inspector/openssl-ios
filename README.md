# openssl-ios

A modern and *maintained* script to compile OpenSSL for iOS and iPadOS applications.

## Usage

It's as simple as:

```
./build-ios.sh <openssl version>
```

Then add the resulting `openssl.xcframework` package to your app and you're finished.

Only maintained versions of OpenSSL are supported. Legacy versions are unsupported, even if you have a support contract with OpenSSL.
Some features of libssl and libcrypto have been disabled by this script.

# License

This build script is licensed under the GPLv3 license. OpenSSL is licensed by the [OpenSSL license](https://www.openssl.org/source/license-openssl-ssleay.txt)

## Export Compliance

Please remember that export/import and/or use of strong cryptography software, providing
cryptography hooks, or even just communicating technical details about cryptography
software is illegal in some parts of the world. By using this script, or importing the
resulting compiled framework in your country, re-distribute it from there or even just
email technical suggestions or even source patches to the authors or other people you are
strongly advised to pay close attention to any laws or regulations which apply to you.
The authors of this script and OpenSSL are not liable for any violations you make here.
So be careful, it is your responsibility. 
