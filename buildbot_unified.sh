#!/bin/bash
echo ""
echo "LineageOS 20 Unified Buildbot"
echo "Executing in 5 seconds - CTRL-C to exit"
echo ""
sleep 5

if [ $# -lt 2 ]
then
    echo "Not enough arguments - exiting"
    echo ""
    exit 1
fi

MODE=${1}
if [ ${MODE} != "device" ] && [ ${MODE} != "treble" ]
then
    echo "Invalid mode - exiting"
    echo ""
    exit 1
fi

NOSYNC=false
PERSONAL=false
for var in "${@:2}"
do
    if [ ${var} == "nosync" ]
    then
        NOSYNC=true
    fi
    if [ ${var} == "personal" ]
    then
        PERSONAL=true
    fi
done

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
BUILD_DATE="$(date +%Y%m%d)"

prep_build() {
    echo "Preparing local manifests"
    mkdir -p .repo/local_manifests
    cp ./lineage_build_unified/local_manifests_${MODE}/*.xml .repo/local_manifests
    echo ""

    echo "Syncing repos"
    repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
    echo ""

    echo "Setting up build environment"
    source build/envsetup.sh &> /dev/null
    mkdir -p ~/build-output
    echo ""

    repopick 321337 -f # Deprioritize important developer notifications
    repopick 321338 -f # Allow disabling important developer notifications
    repopick 321339 -f # Allow disabling USB notifications
    repopick 340916 # SystemUI: add burnIn protection
    repopick 342860 # codec2: Use numClientBuffers to control the pipeline
    repopick 342861 # CCodec: Control the inputs to avoid pipeline overflow
    repopick 342862 # [WA] Codec2: queue a empty work to HAL to wake up allocation thread
    repopick 342863 # CCodec: Use pipelineRoom only for HW decoder
    repopick 342864 # codec2: Change a Info print into Verbose

    # Temporarily revert "13-firewall" changes
    (cd frameworks/base; git revert e91d98e3327a805d1914e7fb1617f3ac081c0689^..cfd9c1e4c8ea855409db5a1ed8f84f4287a37d75 --no-edit)
    (cd packages/apps/Settings; git revert 406607e0c16ed23d918c68f14eb4576ce411bb73 --no-edit)
    (cd packages/modules/Connectivity; git revert 386950b4ea592f2a8e4937444955c9b91ff1f277^..1fa42c03891ba203a321b597fb5709e3a9131f0e --no-edit)
    (cd system/netd; git revert dbf5d67951a0cd6e9b76ca2c08cf2b39ae6d708d^..5c89ab94a797fce13bf858be0f96541bf9f3bfe7 --no-edit)
}

apply_patches() {
    echo "Applying patch group ${1}"
    bash ./lineage_build_unified/apply_patches.sh ./lineage_patches_unified/${1}
}

prep_device() {
    :
}

prep_treble() {
    :
}

finalize_device() {
    :
}

finalize_treble() {
    :
}

build_device() {
    brunch ${1}
    mv $OUT/lineage-*.zip ~/build-output/lineage-20.0-$BUILD_DATE-UNOFFICIAL-${1}$($PERSONAL && echo "-personal" || echo "").zip
}

build_treble() {
    case "${1}" in
        ("64VN") TARGET=gsi_arm64_vN;;
        ("64VS") TARGET=gsi_arm64_vS;;
        ("64GN") TARGET=gsi_arm64_gN;;
        (*) echo "Invalid target - exiting"; exit 1;;
    esac
    lunch lineage_${TARGET}-userdebug
    make installclean
    make -j$(nproc --all) systemimage
    mv $OUT/system.img ~/build-output/lineage-20.0-$BUILD_DATE-UNOFFICIAL-${TARGET}$(${PERSONAL} && echo "-personal" || echo "").img
}

if ${NOSYNC}
then
    echo "ATTENTION: syncing/patching skipped!"
    echo ""
    echo "Setting up build environment"
    source build/envsetup.sh &> /dev/null
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
    if [ ${var} == "nosync" ] || [ ${var} == "personal" ]
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
