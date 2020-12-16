# openssl-ios

A simple script to compile openssl to a dylib framework for iOS apps.

# Instructions

It's as simple as:

```
./build-ios.sh <openssl version>
```

Then add the resulting `openssl.framework` package to your app and you're finished.

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