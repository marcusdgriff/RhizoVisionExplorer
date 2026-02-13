cmake_minimum_required(VERSION 3.28)

# Define the project
project(RhizoVisionExplorer VERSION 2.0.3 DESCRIPTION "RhizoVision Explorer" LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(GNUInstallDirs)

# Set the preferred compilers in order of priority
if(NOT CMAKE_CXX_COMPILER)
    find_program(CLANG_COMPILER NAMES clang++ clang)
    find_program(GCC_COMPILER NAMES g++ gcc)
    find_program(MSVC_COMPILER NAMES cl)

    if(CLANG_COMPILER)
        set(CMAKE_CXX_COMPILER ${CLANG_COMPILER})
    elseif(GCC_COMPILER)
        set(CMAKE_CXX_COMPILER ${GCC_COMPILER})
    elseif(MSVC_COMPILER)
        set(CMAKE_CXX_COMPILER ${MSVC_COMPILER})
    else()
        message(FATAL_ERROR "No suitable compiler found")
    endif()
endif()

# Options to enable or disable AVX-512 and AVX2/FMA support
option(ENABLE_AVX512 "Enable AVX-512 support" OFF) # To be enabled on x86_64 server processors
option(ENABLE_AVX2_FMA "Enable AVX2 and FMA support" ON) # Default support for x86_64 desktop processors
set(RHIZO_EXPECTED_OPENCV_MAJOR_MINOR "4.11" CACHE STRING "Expected OpenCV major.minor for cross-platform parity")
set(RHIZO_EXPECTED_QT_MAJOR_MINOR "6.9" CACHE STRING "Expected Qt major.minor for cross-platform parity")
option(RHIZO_ENFORCE_DEPENDENCY_MAJOR_MINOR "Fail configure when OpenCV/Qt major.minor do not match expected values" ON)

# Detect target architecture to gate x86-specific SIMD compiler flags.
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" RHIZO_SYSTEM_PROCESSOR_LOWER)
if(RHIZO_SYSTEM_PROCESSOR_LOWER MATCHES "^(x86_64|amd64|x64|i[3-6]86)$")
    set(RHIZO_TARGET_IS_X86 TRUE)
else()
    set(RHIZO_TARGET_IS_X86 FALSE)
endif()

set(RHIZO_ENABLE_AVX512_EFFECTIVE ${ENABLE_AVX512})
set(RHIZO_ENABLE_AVX2_FMA_EFFECTIVE ${ENABLE_AVX2_FMA})
if(NOT RHIZO_TARGET_IS_X86)
    if(ENABLE_AVX512 OR ENABLE_AVX2_FMA)
        message(STATUS "Disabling AVX compile flags for non-x86 target processor: ${CMAKE_SYSTEM_PROCESSOR}")
    endif()
    set(RHIZO_ENABLE_AVX512_EFFECTIVE OFF)
    set(RHIZO_ENABLE_AVX2_FMA_EFFECTIVE OFF)
endif()

# Detect the OS
if(WIN32)
    message(STATUS "Configuring for Windows")
elseif(APPLE)
    message(STATUS "Configuring for macOS")
elseif(UNIX)
    message(STATUS "Configuring for Unix/Linux")
else()
    message(FATAL_ERROR "Unsupported OS")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    # Allow installed binaries to locate shared libraries in the same prefix.
    set(CMAKE_MACOSX_RPATH TRUE)
    set(CMAKE_INSTALL_RPATH "@loader_path/../lib")
    set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
endif()

message(STATUS "Using ${CMAKE_CXX_COMPILER_ID} as the C++ compiler")
# Set global CMake build options
if(MSVC)
    # MSVC-specific flags
    set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} /MDd /Zi /Ob0 /Od /RTC1 /DDEBUG /D_CRT_SECURE_NO_WARNINGS")
    set(CMAKE_EXE_LINKER_FLAGS_DEBUG "${CMAKE_EXE_LINKER_FLAGS_DEBUG} /DEBUG /INCREMENTAL")
    
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} /MD /Ox /DNDEBUG")
    set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} /OPT:REF /OPT:ICF")
    
    # Enable AVX-512 and AVX2/FMA support
    if(RHIZO_ENABLE_AVX512_EFFECTIVE)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /arch:AVX512")
    endif()
    if(RHIZO_ENABLE_AVX2_FMA_EFFECTIVE)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /arch:AVX2 /arch:AVX")
    endif()
    
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /fp:precise /fp:strict")
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g -DDEBUG -D_DEBUG -O0")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG")
    
    # Enable AVX-512 and AVX2/FMA support
    if(RHIZO_ENABLE_AVX512_EFFECTIVE)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mavx512")
    endif()
    if(RHIZO_ENABLE_AVX2_FMA_EFFECTIVE)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mavx2 -mfma")
    endif()
    
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-fast-math -frounding-math")
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g -DDEBUG -D_DEBUG -O0")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG")
    
    # Enable AVX-512 and AVX2/FMA support
    if(RHIZO_ENABLE_AVX512_EFFECTIVE)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mavx512")
    endif()
    if(RHIZO_ENABLE_AVX2_FMA_EFFECTIVE)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mavx2 -mfma")
    endif()
    
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-fast-math -frounding-math")
else()
    message(FATAL_ERROR "Unsupported compiler")
endif()

# Find OpenCV
find_package(OpenCV REQUIRED)

# Find Qt6
find_package(Qt6 REQUIRED COMPONENTS Core Widgets Charts Gui OpenGL)
qt_standard_project_setup()

function(rhizo_check_major_minor package_name actual_version expected_major_minor)
    if(NOT actual_version MATCHES "^${expected_major_minor}(\\.|$)")
        if(RHIZO_ENFORCE_DEPENDENCY_MAJOR_MINOR)
            message(FATAL_ERROR
                "${package_name} version mismatch. Expected ${expected_major_minor}.x for cross-platform parity, found ${actual_version}. "
                "Set RHIZO_ENFORCE_DEPENDENCY_MAJOR_MINOR=OFF to bypass."
            )
        else()
            message(WARNING
                "${package_name} version mismatch. Expected ${expected_major_minor}.x for cross-platform parity, found ${actual_version}."
            )
        endif()
    endif()
endfunction()

if(DEFINED OpenCV_VERSION)
    message(STATUS "Using OpenCV version: ${OpenCV_VERSION}")
    rhizo_check_major_minor("OpenCV" "${OpenCV_VERSION}" "${RHIZO_EXPECTED_OPENCV_MAJOR_MINOR}")
endif()

if(DEFINED Qt6Core_VERSION)
    set(RHIZO_QT_FOUND_VERSION "${Qt6Core_VERSION}")
elseif(DEFINED Qt6_VERSION)
    set(RHIZO_QT_FOUND_VERSION "${Qt6_VERSION}")
endif()

if(DEFINED RHIZO_QT_FOUND_VERSION)
    message(STATUS "Using Qt version: ${RHIZO_QT_FOUND_VERSION}")
    rhizo_check_major_minor("Qt6" "${RHIZO_QT_FOUND_VERSION}" "${RHIZO_EXPECTED_QT_MAJOR_MINOR}")
endif()

# Find cvutil
find_package(cvutil REQUIRED)

if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    find_package(X11 REQUIRED)
endif()

get_cmake_property(_variableNames VARIABLES)
foreach (_variableName ${_variableNames})
    if (_variableName MATCHES "^cvutil_")
        message(STATUS "${_variableName}=${${_variableName}}")
    endif()
endforeach()

# Set the Debug postfix
set(CMAKE_DEBUG_POSTFIX "d")

# Enable automatic MOC and RCC for all projects
set(CMAKE_AUTOMOC ON)    # Enable automatic MOC
set(CMAKE_AUTORCC ON)    # Enable automatic RCC
set(CMAKE_AUTOUIC ON)    # Enable automatic UIC

# Define the source files for RoiManager
set(SOURCES
    RhizoVisionExplorer/MainUI.cpp
    RhizoVisionExplorer/feature_extraction.cpp
    RhizoVisionExplorer/rootsegmentprop.cpp
    RhizoVisionExplorer/roottopology.cpp
    RhizoVisionExplorer/resources.qrc
)

# Define the header files
set(HEADERS
    RhizoVisionExplorer/feature_extraction.h
    RhizoVisionExplorer/feature_config.h
    RhizoVisionExplorer/common_types.h
    RhizoVisionExplorer/demo.h
    RhizoVisionExplorer/MainUI.h
    RhizoVisionExplorer/resource.h
    RhizoVisionExplorer/rootsegmentprop.h
    RhizoVisionExplorer/roottopology.h
)

# Include the resource file only if it's WIN32 and MSVC
if(WIN32)
    list(APPEND SOURCES RhizoVisionExplorer/RhizoVisionExplorer.rc)
endif()

# Define the target as an executable.
add_executable(RhizoVisionExplorer WIN32 
    RhizoVisionExplorer/main.cpp
    ${SOURCES}
    ${HEADERS})
add_executable(rv 
    RhizoVisionExplorer/rv.cpp
    RhizoVisionExplorer/indicators/indicators.hpp
    ${SOURCES}
    ${HEADERS})

set_target_properties(RhizoVisionExplorer PROPERTIES DEBUG_POSTFIX ${CMAKE_DEBUG_POSTFIX})
set_target_properties(rv PROPERTIES DEBUG_POSTFIX ${CMAKE_DEBUG_POSTFIX})

# Add the generated resource .cpp file to the target
target_sources(RhizoVisionExplorer PRIVATE ${RESOURCES})

# Include directories (Qt and OpenCV paths are already handled at the solution level)
target_include_directories(RhizoVisionExplorer
    PRIVATE
        #${CMAKE_BINARY_DIR}/library/include
        ${OpenCV_INCLUDE_DIRS}
)

target_include_directories(rv
    PRIVATE
        #${CMAKE_BINARY_DIR}/library/include
        ${OpenCV_INCLUDE_DIRS}
)

# Link libraries (cvutil depends on PluginManager and RoiManager)
target_link_libraries(RhizoVisionExplorer
    PRIVATE
        ${OpenCV_LIBS}
        Qt6::Core
        Qt6::Widgets
        Qt6::Charts
        Qt6::Gui
        Qt6::OpenGL
        cvutil::cvutil
        cvutil::PluginManager
        cvutil::RoiManager
)

target_link_libraries(rv
    PRIVATE
        ${OpenCV_LIBS}
        Qt6::Core
        Qt6::Widgets
        Qt6::Charts
        Qt6::Gui
        Qt6::OpenGL
        cvutil::cvutil
        cvutil::PluginManager
        cvutil::RoiManager
)

set(CPACK_PROPERTIES_FILE "${CMAKE_BINARY_DIR}/RhizoVisionCPackProperties-$<CONFIG>.cmake")
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/RhizoVisionCPackProperties-$<CONFIG>.cmake" #allows use of generator expression to retrieve CONFIG
        CONTENT "set(CPACK_BUILD_TYPE \"$<CONFIG>\")\n")

# Include code for installing the targets
include(CMake/cvutilInstallTargets.cmake)

# Include the CPack module
if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    include(CMake/PackageWindows.cmake)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    # Check if we are using a conda env or not
    if (DEFINED ENV{CONDA_PREFIX})
        message(STATUS "Using conda environment: $ENV{CONDA_PREFIX} not generating a Debian package.")
        # Do not package if inside a conda environment
    else()
        message(STATUS "Not using conda environment, use CPack to create a Debian package.")
        include(CMake/PackageLinux.cmake)
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    message(STATUS "macOS build selected; DEB/Windows packaging is skipped.")
endif()
