# BlueWakeGame.framework: BlueWake's Wind Waker, as a framework PadHub loads
# and starts (BlueWakeHubGame.mm) instead of an app of its own. Included at the
# end of BlueWake's apple/ios/CMakeLists.txt when it is configured with
# -DBLUEWAKE_PADHUB=ON (scripts/build-bluewake.sh), so it builds from the same
# sources, definitions and libraries as the BlueWake app. It exports only its
# PadHub class: its SDL, Aurora and Dawn stay its own.
set(PADHUB_DIR "" CACHE PATH "PadHub's checkout")
set(PADHUB_BUNDLE_ID "org.padhub.app" CACHE STRING "PadHub's bundle identifier")
set(NSOGCKIT_FRAMEWORK_DIR "" CACHE PATH "The folder with PadHub's NSOGCKit.framework for this SDK")

add_library(BlueWakeGame SHARED
    src/ios_entry.m
    src/disc_import.c
    ${BLUEWAKE_PLATFORM_SOURCES}
    ${BLUEWAKE_HOST_SOURCES}
    ${PADHUB_DIR}/Games/BlueWake/BlueWakeHubGame.mm)
target_link_libraries(BlueWakeGame PRIVATE gxruntime GXRuntime::aurora z bluewake_wwhd_disc_crypto)
if(TARGET xxhash)
    target_link_libraries(BlueWakeGame PRIVATE xxhash)
endif()
if(BLUEWAKE_IOS_ENABLE_DSP)
    target_compile_definitions(BlueWakeGame PRIVATE BLUEWAKE_HAS_DSP_ADAPTER=1)
    target_link_libraries(BlueWakeGame PRIVATE bluewake_dsp_adapter)
endif()
target_include_directories(BlueWakeGame PRIVATE
    ${BLUEWAKE_HOST_SRC}
    ${GXRUNTIME_DIR}/include
    ${BLUEWAKE_REPO_ROOT}/ref/recompcore/Source/Core/Core/PowerPC/StaticRecomp
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${PADHUB_DIR}/Games)
target_compile_definitions(BlueWakeGame PRIVATE
    DOLRECOMP_CPU_HEADER="core/cpu.h"
    BLUEWAKE_ENABLE_DEVELOPER_TRACING=$<BOOL:${BLUEWAKE_IOS_DEVELOPER_TRACING}>
    BLUEWAKE_EDGE_CENSUS=0
    ${BLUEWAKE_PLATFORM_DEFINITIONS}
    BLUEWAKE_PADHUB=1)
target_compile_options(BlueWakeGame PRIVATE -fobjc-arc "-F${NSOGCKIT_FRAMEWORK_DIR}")
target_link_libraries(BlueWakeGame PRIVATE
    "-framework Foundation" "-framework UIKit" "-framework GameController"
    "-framework QuartzCore" "-framework AVFoundation" "-framework UniformTypeIdentifiers"
    "-F${NSOGCKIT_FRAMEWORK_DIR}" "-framework NSOGCKit")
target_link_options(BlueWakeGame PRIVATE
    "LINKER:-exported_symbols_list,${PADHUB_DIR}/Games/BlueWake/exports.txt")
set_target_properties(BlueWakeGame PROPERTIES
    FRAMEWORK TRUE
    LINKER_LANGUAGE CXX
    OUTPUT_NAME BlueWakeGame
    INSTALL_NAME_DIR "@rpath"
    BUILD_WITH_INSTALL_NAME_DIR ON
    INSTALL_RPATH "@executable_path/Frameworks"   # PadHub's NSOGCKit
    BUILD_WITH_INSTALL_RPATH ON
    MACOSX_FRAMEWORK_IDENTIFIER ${PADHUB_BUNDLE_ID}.BlueWakeGame
    MACOSX_FRAMEWORK_INFO_PLIST ${PADHUB_DIR}/Games/BlueWake/Info.plist.in
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING ${BLUEWAKE_VERSION}
    MACOSX_FRAMEWORK_BUNDLE_VERSION ${BLUEWAKE_BUILD})
