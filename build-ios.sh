#!/bin/sh
set -e

if [ -z "${1}" ]; then
    echo "Usage: ${0} <OpenSSL Version>"
    exit 1
fi

VERSION=$1
shift
BUILD_ARGS="$@"

############
# DOWNLOAD #
############

ARCHIVE=openssl-${VERSION}.tar.gz
if [ ! -f ${ARCHIVE} ]; then
    echo "Downloading openssl ${VERSION}..."
    curl -L "https://www.openssl.org/source/openssl-${VERSION}.tar.gz" > "${ARCHIVE}"
fi

if [ ! -z "${GPG_VERIFY}" ]; then
    echo "Verifying signature for openssl-${VERSION}.tar.gz..."
    rm -f "${ARCHIVE}.asc"
    curl -L "https://www.openssl.org/source/openssl-${VERSION}.tar.gz.asc" > "${ARCHIVE}.asc"
    gpg --verify "${ARCHIVE}.asc" "${ARCHIVE}"
    echo "Verified signature for openssl-${VERSION}.tar.gz successfully!"
fi

###########
# COMPILE #
###########

BUILDDIR=build

function build() {
    ARCH=${1}
    HOST=${2}
    SDK=${3}
    SDKDIR=$(xcrun --sdk ${SDK} --show-sdk-path)
    LOG="../${ARCH}-${SDK}_build.log"
    echo "Building openssl for ${ARCH}-${SDK}..."

    WORKDIR=openssl_${ARCH}-${SDK}
    mkdir "${WORKDIR}"
    tar -xzf "../${ARCHIVE}" -C "${WORKDIR}" --strip-components 1
    cd "${WORKDIR}"

    for FILE in $(find ../../patches -name '*.patch'); do
        patch -p1 < ${FILE}
    done

    export CC=$(xcrun -find -sdk ${SDK} clang)
    export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${SDKDIR} -m${SDK}-version-min=12.0"
    export LDFLAGS="-arch ${ARCH} -isysroot ${SDKDIR}"
    BUILD_ARGS="-no-shared -no-ui-console -no-tests -no-stdio -no-threads -no-legacy -no-ssl2 -no-ssl3 -no-asm -no-weak-ssl-ciphers ${BUILD_ARGS}"

    echo "build variables: CC=\"${CC}\" CFLAGS=\"${CFLAGS}\" LDFLAGS=\"${LDFLAGS}\"" >> "${LOG}"
    echo "configure parameters: ${BUILD_ARGS}" >> "${LOG}"

    ./configure \
        $BUILD_ARGS \
        --prefix=$(pwd)/artifacts \
        ${HOST} >> "${LOG}" 2>&1
    perl configdata.pm --dump >> ../${ARCH}-${SDK}_configuration.log

    make -j $(sysctl -n hw.logicalcpu_max) >> "${LOG}" 2>&1
    make install >> "${LOG}" 2>&1

    cd ../
}

rm -rf ${BUILDDIR}
mkdir ${BUILDDIR}
cd ${BUILDDIR}

build arm64    ios64-xcrun         iphoneos
build arm64    iossimulator-xcrun  iphonesimulator
build x86_64   iossimulator-xcrun  iphonesimulator

cd ../

###########
# PACKAGE #
###########

# Merge the arm64 and x86_64 binaries for the simulator together
lipo \
   -arch arm64  ${BUILDDIR}/openssl_arm64-iphonesimulator/artifacts/lib/libssl.a \
   -arch x86_64 ${BUILDDIR}/openssl_x86_64-iphonesimulator/artifacts/lib/libssl.a \
   -create -output ${BUILDDIR}/libssl.a
lipo \
   -arch arm64  ${BUILDDIR}/openssl_arm64-iphonesimulator/artifacts/lib/libcrypto.a \
   -arch x86_64 ${BUILDDIR}/openssl_x86_64-iphonesimulator/artifacts/lib/libcrypto.a \
   -create -output ${BUILDDIR}/libcrypto.a

rm -rf libssl.xcframework
xcodebuild -create-xcframework \
    -library ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/lib/libssl.a     -headers ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/include/openssl \
    -library ${BUILDDIR}/libssl.a                                          -headers ${BUILDDIR}/openssl_arm64-iphonesimulator/artifacts/include/openssl \
    -output libssl.xcframework
plutil -insert CFBundleVersion -string ${VERSION} libssl.xcframework/Info.plist

rm -rf libcrypto.xcframework
xcodebuild -create-xcframework \
    -library ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/lib/libcrypto.a     -headers ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/include/openssl \
    -library ${BUILDDIR}/libcrypto.a                                          -headers ${BUILDDIR}/openssl_arm64-iphonesimulator/artifacts/include/openssl \
    -output libcrypto.xcframework
plutil -insert CFBundleVersion -string ${VERSION} libcrypto.xcframework/Info.plist

# Create a traditional .framework that combines libssl and libcrypto for each platform
rm -rf ${BUILDDIR}/iphoneos/openssl.framework ${BUILDDIR}/iphonesimulator/openssl.framework
mkdir -p ${BUILDDIR}/iphoneos/openssl.framework/Headers ${BUILDDIR}/iphonesimulator/openssl.framework/Headers

libtool -no_warning_for_no_symbols -static -o ${BUILDDIR}/iphoneos/openssl.framework/openssl ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/lib/libssl.a ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/lib/libcrypto.a
cp -r ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/include/openssl/*.h ${BUILDDIR}/iphoneos/openssl.framework/Headers
libtool -no_warning_for_no_symbols -static -o ${BUILDDIR}/iphonesimulator/openssl.framework/openssl ${BUILDDIR}/libssl.a ${BUILDDIR}/libcrypto.a
cp -r ${BUILDDIR}/openssl_arm64-iphonesimulator/artifacts/include/openssl/*.h ${BUILDDIR}/iphonesimulator/openssl.framework/Headers

rm -rf openssl.xcframework
xcodebuild -create-xcframework \
    -framework ${BUILDDIR}/iphoneos/openssl.framework \
    -framework ${BUILDDIR}/iphonesimulator/openssl.framework \
    -output openssl.xcframework
plutil -insert CFBundleVersion -string ${VERSION} openssl.xcframework/Info.plist
