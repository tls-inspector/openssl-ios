#!/bin/sh
set -e

if [ -z "${1}" ]; then
    echo "Usage: ${0} <OpenSSL Version>"
    exit 1
fi

############
# DOWNLOAD #
############

VERSION=${1}
ARCHIVE=openssl-${VERSION}.tar.gz
echo "Downloading openssl ${VERSION}"

if [ ! -f ${ARCHIVE} ]; then
    curl "https://www.openssl.org/source/openssl-${VERSION}.tar.gz" > "${ARCHIVE}"
fi

###########
# COMPILE #
###########

export OUTDIR=output
export BUILDDIR=build
export IPHONEOS_DEPLOYMENT_TARGET="9.3"
export CC=$(xcrun -find -sdk iphoneos clang)

function build() {
    ARCH=${1}
    HOST=${2}
    SDKDIR=${3}
    LOG="../${ARCH}_build.log"
    echo "Building openssl for ${ARCH}..."

    WORKDIR=openssl_${ARCH}
    mkdir "${WORKDIR}"
    tar -xzf "../${ARCHIVE}" -C "${WORKDIR}" --strip-components 1
    cd "${WORKDIR}"

    export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${SDKDIR} -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"

    export LDFLAGS="-arch ${ARCH} -isysroot ${SDKDIR}"

    ./configure -shared -no-engine -no-async -no-hw ${HOST} > "${LOG}" 2>&1

    make -j $(sysctl -n hw.logicalcpu_max) > "${LOG}" 2>&1

    cd ../
}

rm -rf ${OUTDIR} ${BUILDDIR}
mkdir ${OUTDIR}
mkdir ${BUILDDIR}
cd ${BUILDDIR}

build armv7s   ios-xcrun           $(xcrun --sdk iphoneos --show-sdk-path)
build arm64    ios64-xcrun         $(xcrun --sdk iphoneos --show-sdk-path)
build i386   iossimulator-xcrun    $(xcrun --sdk iphonesimulator --show-sdk-path)
build x86_64   iossimulator-xcrun  $(xcrun --sdk iphonesimulator --show-sdk-path)

cd ../

lipo ${BUILDDIR}/openssl_armv7s/libssl.a \
   -arch arm64 ${BUILDDIR}/openssl_arm64/libssl.a \
   -arch i386 ${BUILDDIR}/openssl_i386/libssl.a \
   -arch x86_64 ${BUILDDIR}/openssl_x86_64/libssl.a \
   -create -output ${OUTDIR}/libssl.a

lipo ${BUILDDIR}/openssl_armv7s/libcrypto.a \
   -arch arm64 ${BUILDDIR}/openssl_arm64/libcrypto.a \
   -arch i386 ${BUILDDIR}/openssl_i386/libcrypto.a \
   -arch x86_64 ${BUILDDIR}/openssl_x86_64/libcrypto.a \
   -create -output ${OUTDIR}/libcrypto.a

###########
# PACKAGE #
###########

FWNAME=openssl

if [ -d ${FWNAME}.framework ]; then
    echo "Removing previous ${FWNAME}.framework copy"
    rm -rf ${FWNAME}.framework
fi

LIBTOOL_FLAGS="-no_warning_for_no_symbols -static"

echo "Creating ${FWNAME}.framework"
mkdir -p ${FWNAME}.framework/Headers/
libtool ${LIBTOOL_FLAGS} -o ${FWNAME}.framework/${FWNAME} ${OUTDIR}/libssl.a ${OUTDIR}/libcrypto.a
cp -r ${BUILDDIR}/openssl_arm64/include/${FWNAME}/*.h ${FWNAME}.framework/Headers/

rm -rf ${BUILDDIR}
rm -rf ${OUTDIR}

cp "Info.plist" ${FWNAME}.framework/Info.plist

check_bitcode=$(otool -arch arm64 -l ${FWNAME}.framework/${FWNAME} | grep __bitcode)
if [ -z "${check_bitcode}" ]
then
    echo "INFO: ${FWNAME}.framework doesn't contain Bitcode"
else
    echo "INFO: ${FWNAME}.framework contains Bitcode"
fi
