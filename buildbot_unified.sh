#!/bin/bash
echo ""
echo "LineageOS 21 Unified Buildbot"
echo ""

if [ $# -lt 2 ]
then
    echo "Not enough arguments - exiting"
    echo ""
    exit 1
fi

MODE=${1}
if [ ${MODE} != "treble" ]
then
    echo "Invalid mode - exiting"
    echo ""
    exit 1
fi

NOSYNC=false
PERSONAL=false
SIGNABLE=true
NOCLEAN=false
for var in "${@:2}"
do
    if [ ${var} == "nosync" ]
    then
        NOSYNC=true
    fi
    if [ ${var} == "personal" ]
    then
        PERSONAL=true
        SIGNABLE=false
    fi
    if [ ${var} == "noclean" ]
    then
        NOCLEAN=true
    fi
done

# Set the home directory to the original user's home
export HOME=$(eval echo ~$(logname))

if [ ! -d "$HOME/.android-certs" ]; then
    read -n1 -r -p $"\$HOME/.android-certs not found - CTRL-C to exit, or any other key to continue"
    echo ""
    SIGNABLE=false
fi

# Abort early on error
set -eE
trap '(\
echo;\
echo \!\!\! An error happened during script execution;\
echo \!\!\! Please check console output for bad sync,;\
echo \!\!\! failed patch application, etc.;\
echo\
)' ERR

START=`date +%s`
BUILD_DATE="$(date -u +%Y%m%d)"
mkdir -p release

prep_build() {
    echo "Preparing local manifests"
    mkdir -p .repo/local_manifests
    cp ./lineage_build_unified/local_manifests_${MODE}/*.xml .repo/local_manifests
    echo ""

    echo "Syncing repos"
    repo sync -c --force-sync --no-clone-bundle --no-tags -j8
    echo ""

    echo "Setting up build environment"
    source build/envsetup.sh &> /dev/null
    source vendor/lineage/vars/aosp_target_release
    mkdir -p ~/build-output
    echo ""

    repopick 321337 -r -f # Deprioritize important developer notifications
    repopick 321338 -r -f # Allow disabling important developer notifications
    repopick 321339 -r -f # Allow disabling USB notifications
    repopick 368923 -r -f # Launcher3: Show clear all button in recents overview
}

apply_patches() {
    echo "Applying patch group ${1}"
    bash ./lineage_build_unified/apply_patches.sh ./lineage_patches_unified/${1}
}

prep_treble() {
    apply_patches patches_treble_prerequisite
    apply_patches patches_treble_td
}

finalize_treble() {
    cd device/phh/treble
    git clean -fdx
    bash generate.sh lineage
    cd ../../..
    cd treble_app
    bash build.sh release
    cp TrebleApp.apk ../vendor/hardware_overlay/TrebleApp/app.apk
    cd ..
    cd vendor/hardware_overlay
    git add TrebleApp/app.apk
    git commit -m "[TEMP] Up TrebleApp to $BUILD_DATE"
    cd ../..
}

build_treble() {
    case "${1}" in
        ("A64VN") TARGET=a64_bvN;;
        ("A64VS") TARGET=a64_bvS;;
        ("A64GN") TARGET=a64_bgN;;
        ("64VN") TARGET=arm64_bvN;;
        ("64VS") TARGET=arm64_bvS;;
        ("64GN") TARGET=arm64_bgN;;
        (*) echo "Invalid target - exiting"; exit 1;;
    esac
    lunch lineage_${TARGET}-${aosp_target_release}-userdebug
    if [ ${NOCLEAN} = false ]
    then
		make installclean
    fi
    WITH_ADB_INSECURE=true make -j$(lscpu -b -p=Core,Socket | grep -v '^#' | sort -u | wc -l) systemimage
    SIGNED=false
    if [ ${SIGNABLE} = true ] && [[ ${TARGET} == *_bg? ]]
    then
        WITH_ADB_INSECURE=true make -j$(lscpu -b -p=Core,Socket | grep -v '^#' | sort -u | wc -l) target-files-package otatools
        bash ./lineage_build_unified/sign_target_files.sh $OUT/signed-target_files.zip
        unzip -joq $OUT/signed-target_files.zip IMAGES/system.img -d $OUT
        SIGNED=true
        echo ""
    fi
    xz -c $OUT/system.img -T0 > release/lineage-21.0-$BUILD_DATE-UNOFFICIAL-${TARGET}$(${PERSONAL} && echo "-personal" || echo "")$(${SIGNED} && echo "-signed" || echo "").img.xz
    #mv $OUT/system.img release/lineage-21.0-$BUILD_DATE-UNOFFICIAL-${TARGET}$(${PERSONAL} && echo "-personal" || echo "")$(${SIGNED} && echo "-signed" || echo "").img
    #make vndk-test-sepolicy
}

if ${NOSYNC}
then
    echo "ATTENTION: syncing/patching skipped!"
    echo ""
    echo "Setting up build environment"
    source build/envsetup.sh &> /dev/null
    source vendor/lineage/vars/aosp_target_release
    mkdir -p ~/build-output
    echo ""
else
    prep_build
    echo "Applying patches"
    prep_${MODE}
    apply_patches patches_platform
    apply_patches patches_${MODE}
    if ${PERSONAL}
    then
        apply_patches patches_platform_personal
        apply_patches patches_${MODE}_personal
    fi
    finalize_${MODE}
    echo ""
fi


for var in "${@:2}"
do
    if [ ${var} == "nosync" ] || [ ${var} == "personal" ] || [ ${var} == "noclean" ]
    then
        continue
    fi
    echo "Starting $(${PERSONAL} && echo "personal " || echo "")build for ${MODE} ${var}"
    build_${MODE} ${var}
done
ls ~/build-output | grep 'lineage' || true

END=`date +%s`
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))
echo "Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo ""
