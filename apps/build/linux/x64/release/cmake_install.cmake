# Install script for directory: /home/logan/Projects/slopped-pangolin/apps/linux

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "Release")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Install shared libraries without execute permission?
if(NOT DEFINED CMAKE_INSTALL_SO_NO_EXE)
  set(CMAKE_INSTALL_SO_NO_EXE "1")
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "FALSE")
endif()

# Set path to fallback-tool for dependency-resolution.
if(NOT DEFINED CMAKE_OBJDUMP)
  set(CMAKE_OBJDUMP "/usr/bin/objdump")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  
  file(REMOVE_RECURSE "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/")
  
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  if(EXISTS "$ENV{DESTDIR}/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/dahlia_apps" AND
     NOT IS_SYMLINK "$ENV{DESTDIR}/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/dahlia_apps")
    file(RPATH_CHECK
         FILE "$ENV{DESTDIR}/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/dahlia_apps"
         RPATH "$ORIGIN/lib")
  endif()
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/dahlia_apps")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle" TYPE EXECUTABLE FILES "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/intermediates_do_not_run/dahlia_apps")
  if(EXISTS "$ENV{DESTDIR}/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/dahlia_apps" AND
     NOT IS_SYMLINK "$ENV{DESTDIR}/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/dahlia_apps")
    file(RPATH_CHANGE
         FILE "$ENV{DESTDIR}/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/dahlia_apps"
         OLD_RPATH "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/handy_window:/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/screen_retriever_linux:/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/url_launcher_linux:/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/window_manager:/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/yaru_window_linux:/home/logan/Projects/slopped-pangolin/apps/linux/flutter/ephemeral:/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/handy_window/libhandy:"
         NEW_RPATH "$ORIGIN/lib")
    if(CMAKE_INSTALL_DO_STRIP)
      execute_process(COMMAND "/usr/bin/strip" "$ENV{DESTDIR}/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/dahlia_apps")
    endif()
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/data/icudtl.dat")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/data" TYPE FILE FILES "/home/logan/Projects/slopped-pangolin/apps/linux/flutter/ephemeral/icudtl.dat")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib/libflutter_linux_gtk.so")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib" TYPE FILE FILES "/home/logan/Projects/slopped-pangolin/apps/linux/flutter/ephemeral/libflutter_linux_gtk.so")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib/libhandy_window_plugin.so")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib" TYPE FILE FILES "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/handy_window/libhandy_window_plugin.so")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib/libhandy_flutter.so")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib" TYPE FILE FILES "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/handy_window/libhandy/libhandy_flutter.so")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib/libscreen_retriever_linux_plugin.so")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib" TYPE FILE FILES "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/screen_retriever_linux/libscreen_retriever_linux_plugin.so")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib/liburl_launcher_linux_plugin.so")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib" TYPE FILE FILES "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/url_launcher_linux/liburl_launcher_linux_plugin.so")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib/libwindow_manager_plugin.so")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib" TYPE FILE FILES "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/window_manager/libwindow_manager_plugin.so")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib/libyaru_window_linux_plugin.so")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib" TYPE FILE FILES "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/yaru_window_linux/libyaru_window_linux_plugin.so")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib/libflutter_pty.so")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib" TYPE FILE FILES "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/flutter_pty/shared/libflutter_pty.so")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib/")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib" TYPE DIRECTORY FILES "/home/logan/Projects/slopped-pangolin/apps/build/native_assets/linux/")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  
  file(REMOVE_RECURSE "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/data/flutter_assets")
  
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/data/flutter_assets")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/data" TYPE DIRECTORY FILES "/home/logan/Projects/slopped-pangolin/apps/build//flutter_assets")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib/libapp.so")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/bundle/lib" TYPE FILE FILES "/home/logan/Projects/slopped-pangolin/apps/build/lib/libapp.so")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for each subdirectory.
  include("/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/flutter/cmake_install.cmake")
  include("/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/runner/cmake_install.cmake")
  include("/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/handy_window/cmake_install.cmake")
  include("/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/screen_retriever_linux/cmake_install.cmake")
  include("/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/url_launcher_linux/cmake_install.cmake")
  include("/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/window_manager/cmake_install.cmake")
  include("/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/yaru_window_linux/cmake_install.cmake")
  include("/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/flutter_pty/cmake_install.cmake")
  include("/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/plugins/jni/cmake_install.cmake")

endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
if(CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/install_local_manifest.txt"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
if(CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_COMPONENT MATCHES "^[a-zA-Z0-9_.+-]+$")
    set(CMAKE_INSTALL_MANIFEST "install_manifest_${CMAKE_INSTALL_COMPONENT}.txt")
  else()
    string(MD5 CMAKE_INST_COMP_HASH "${CMAKE_INSTALL_COMPONENT}")
    set(CMAKE_INSTALL_MANIFEST "install_manifest_${CMAKE_INST_COMP_HASH}.txt")
    unset(CMAKE_INST_COMP_HASH)
  endif()
else()
  set(CMAKE_INSTALL_MANIFEST "install_manifest.txt")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "/home/logan/Projects/slopped-pangolin/apps/build/linux/x64/release/${CMAKE_INSTALL_MANIFEST}"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
