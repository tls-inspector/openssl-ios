#!/bin/bash
set -e

################
# PROCESS ARGS #
################

VERIFY=0
OPENSSL_VERSION=0
SWIFT=0
USE_GH_CLI=0

while getopts :o:vsg OPTION; do
    case $OPTION in
        o) OPENSSL_VERSION=$OPTARG;;
        v) VERIFY=1;;
        s) SWIFT=1;;
        g) USE_GH_CLI=1;;
        ?) echo "Error: Invalid option was specified -$OPTARG";exit 1;;
    esac
done
if [ "$OPTIND" -ge 2 ]; then
    shift "$((OPTIND - 2))"
    shift 1
else
    shift "$((OPTIND - 1))"
fi

if ! command -v jq 2>&1 >/dev/null; then
    echo "The 'jq' utility must be installed, otherwise you must specify the openssl version to use."
    exit 1
fi

BUILD_ARGS="$*"
USERAGENT="github.com/tls-inspector/openssl-ios"

function github_api() {
    API_PATH=$1

    if [[ $USE_GH_CLI == 1 ]]; then
        gh api $API_PATH
    else
        curl -Ss -A "${USERAGENT}" "https://api.github.com/$API_PATH"
    fi
}

if [[ $OPENSSL_VERSION == 0 ]]; then
    OPENSSL_VERSION=$(github_api repos/tls-inspector/openssl-ios/releases/latest | jq -r .name)
fi
echo "Using OpenSSL ${OPENSSL_VERSION}"

###############################
# DOWNLOAD & VERIFY ARTIFACTS #
###############################

# Download openssl
ARCHIVE=openssl-${OPENSSL_VERSION}.tar.gz
if [ ! -f "${ARCHIVE}" ]; then
    echo "Downloading openssl ${OPENSSL_VERSION}..."
    curl -A "${USERAGENT}" -L "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" > "${ARCHIVE}"
fi

# Verify openssl
if [[ $VERIFY == 1 ]]; then
    echo "Verifying signature for ${ARCHIVE}"
    if [ ! -f "${ARCHIVE}.asc" ]; then
        curl -A "${USERAGENT}" -L "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz.asc" > "${ARCHIVE}.asc"
    fi
    gpg --verify "${ARCHIVE}.asc" "${ARCHIVE}" >/dev/null
    echo "Verified signature for ${ARCHIVE} successfully!"
fi

###########
# COMPILE #
###########

BUILDDIR=build

function build() {
    ARCH=${1}
    HOST=${2}
    SDK=${3}
    echo "Building openssl for ${ARCH}-${SDK}..."
    SDKDIR=$(xcrun --sdk ${SDK} --show-sdk-path)
    LOG="../${ARCH}-${SDK}_build.log"

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

    CONFIGURE_ARGS="${BUILD_ARGS} -no-shared -no-ui-console -no-tests -no-stdio -no-threads -no-legacy -no-ssl2 -no-ssl3 -no-asm -no-weak-ssl-ciphers"

    echo "build variables: CC=\"${CC}\" CFLAGS=\"${CFLAGS}\" LDFLAGS=\"${LDFLAGS}\"" >> "${LOG}"
    echo "configure parameters: ${CONFIGURE_ARGS}" >> "${LOG}"

    ./configure \
        $CONFIGURE_ARGS \
        --prefix=$(pwd)/artifacts \
        ${HOST} >> "${LOG}" 2>&1
    perl configdata.pm --dump >> ../${ARCH}-${SDK}_configuration.log

    make -j $(sysctl -n hw.logicalcpu_max) >> "${LOG}" 2>&1
    make install >> "${LOG}" 2>&1

    # Deprecated file (openssl should just remove it)
    rm artifacts/include/openssl/asn1_mac.h

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
plutil -insert CFBundleVersion -string ${OPENSSL_VERSION} libssl.xcframework/Info.plist

rm -rf libcrypto.xcframework
xcodebuild -create-xcframework \
    -library ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/lib/libcrypto.a     -headers ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/include/openssl \
    -library ${BUILDDIR}/libcrypto.a                                          -headers ${BUILDDIR}/openssl_arm64-iphonesimulator/artifacts/include/openssl \
    -output libcrypto.xcframework
plutil -insert CFBundleVersion -string ${OPENSSL_VERSION} libcrypto.xcframework/Info.plist

# Create a traditional .framework that combines libssl and libcrypto for each platform
rm -rf ${BUILDDIR}/iphoneos/openssl.framework ${BUILDDIR}/iphonesimulator/openssl.framework
mkdir -p ${BUILDDIR}/iphoneos/openssl.framework/Headers ${BUILDDIR}/iphonesimulator/openssl.framework/Headers

libtool -no_warning_for_no_symbols -static -o ${BUILDDIR}/iphoneos/openssl.framework/openssl ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/lib/libssl.a ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/lib/libcrypto.a
cp -r ${BUILDDIR}/openssl_arm64-iphoneos/artifacts/include/openssl/*.h ${BUILDDIR}/iphoneos/openssl.framework/Headers
libtool -no_warning_for_no_symbols -static -o ${BUILDDIR}/iphonesimulator/openssl.framework/openssl ${BUILDDIR}/libssl.a ${BUILDDIR}/libcrypto.a
cp -r ${BUILDDIR}/openssl_arm64-iphonesimulator/artifacts/include/openssl/*.h ${BUILDDIR}/iphonesimulator/openssl.framework/Headers

if [[ $SWIFT == 1 ]]; then
    ./inject_module_map.sh iphoneos
    ./inject_module_map.sh iphonesimulator
fi

rm -rf openssl.xcframework
xcodebuild -create-xcframework \
    -framework ${BUILDDIR}/iphoneos/openssl.framework \
    -framework ${BUILDDIR}/iphonesimulator/openssl.framework \
    -output openssl.xcframework
plutil -insert CFBundleVersion -string ${OPENSSL_VERSION} openssl.xcframework/Info.plist
