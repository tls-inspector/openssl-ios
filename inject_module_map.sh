#!/bin/sh
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <platform>"
    exit 1
fi

PLATFORM=${1}
mkdir -p build/${PLATFORM}/openssl.framework/Modules
echo "framework module OpenSSL {" > build/${PLATFORM}/openssl.framework/Modules/module.modulemap
echo "    header \"shim.h\"" >> build/${PLATFORM}/openssl.framework/Modules/module.modulemap
for HEADER in $(ls build/${PLATFORM}/openssl.framework/Headers); do
    echo "    header \"${HEADER}\"" >> build/${PLATFORM}/openssl.framework/Modules/module.modulemap
done
echo "    export *" >> build/${PLATFORM}/openssl.framework/Modules/module.modulemap
echo "}" >> build/${PLATFORM}/openssl.framework/Modules/module.modulemap
cp shim.h build/${PLATFORM}/openssl.framework/Headers
