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

if [ ! -f ${ARCHIVE} ]; then
    echo "Downloading openssl ${VERSION}"
    curl "https://www.openssl.org/source/openssl-${VERSION}.tar.gz" > "${ARCHIVE}"
fi

###########
# COMPILE #
###########

export OUTDIR=output
export BUILDDIR=build
export MINIMUM_IOS_VERSION="12.0"
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

    for FILE in $(find ../../patches -name '*.patch'); do
        patch -p1 < ${FILE}
    done

    export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${SDKDIR} -mios-version-min=${MINIMUM_IOS_VERSION} -miphoneos-version-min=${MINIMUM_IOS_VERSION}"
    export LDFLAGS="-arch ${ARCH} -isysroot ${SDKDIR}"

    ./configure -shared -no-ui-console -no-tests -no-stdio -lpthread ${HOST} > "${LOG}" 2>&1
    perl configdata.pm --dump > ../${ARCH}_configuration.txt

    make -j $(sysctl -n hw.logicalcpu_max) >> "${LOG}" 2>&1

    cd ../
}

rm -rf ${OUTDIR} ${BUILDDIR}
mkdir ${OUTDIR}
mkdir ${BUILDDIR}
cd ${BUILDDIR}

build arm64    ios64-xcrun         $(xcrun --sdk iphoneos --show-sdk-path)
build x86_64   iossimulator-xcrun  $(xcrun --sdk iphonesimulator --show-sdk-path)

cd ../

rm ${ARCHIVE}

lipo \
   -arch arm64  ${BUILDDIR}/openssl_arm64/libssl.a \
   -arch x86_64 ${BUILDDIR}/openssl_x86_64/libssl.a \
   -create -output ${OUTDIR}/libssl.a

lipo \
   -arch arm64  ${BUILDDIR}/openssl_arm64/libcrypto.a \
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
