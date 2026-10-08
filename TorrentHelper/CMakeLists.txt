cmake_minimum_required(VERSION 3.20)
project(mcdownloader-torrentd LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "")

if(NOT DEFINED MCD_VERSION)
  set(MCD_VERSION "1.0.0")
endif()

find_package(LibtorrentRasterbar REQUIRED)

add_executable(mcdownloader-torrentd src/main.cpp)

target_compile_definitions(mcdownloader-torrentd PRIVATE MCD_VERSION="${MCD_VERSION}")
target_link_libraries(mcdownloader-torrentd PRIVATE LibtorrentRasterbar::torrent-rasterbar)

target_compile_options(mcdownloader-torrentd PRIVATE -Wall -Wextra)

if(APPLE)
  # libtorrent needs the C++ runtime and links to boost; a static build folds
  # everything into one binary so the app can ship a single executable.
  find_package(Boost REQUIRED)
  target_include_directories(mcdownloader-torrentd PRIVATE ${Boost_INCLUDE_DIRS})
endif()

install(TARGETS mcdownloader-torrentd RUNTIME DESTINATION bin)
