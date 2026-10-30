

# shared cpack variables
set(CPACK_PACKAGE_NAME "RStudio")
set(CPACK_PACKAGE_DESCRIPTION "RStudio")
set(CPACK_PACKAGE_VENDOR "Posit Software")
set(CPACK_PACKAGE_CONTACT "RStudio <info@posit.co>")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "RStudio")

# SUPERR CHANGE: the desktop package carries the SuperR identity from
# package/superr/product.json, so it installs beside RStudio instead of over it
include("${CMAKE_CURRENT_SOURCE_DIR}/superr/superr-product.cmake")
if(WIN32)
   set(CPACK_PACKAGE_NAME "${SUPERR_productName}")
   set(CPACK_PACKAGE_DESCRIPTION "${SUPERR_description}")
   set(CPACK_PACKAGE_VENDOR "${SUPERR_vendor}")
   set(CPACK_PACKAGE_CONTACT "${SUPERR_homepage}")
   set(CPACK_PACKAGE_INSTALL_DIRECTORY "${SUPERR_installDirectory}")
   set(CPACK_NSIS_DISPLAY_NAME "${SUPERR_productName} ${SUPERR_DISPLAY_VERSION}")
   set(CPACK_NSIS_PACKAGE_NAME "${SUPERR_productName} ${SUPERR_DISPLAY_VERSION}")
   set(CPACK_NSIS_URL_INFO_ABOUT "${SUPERR_homepage}")
   set(CPACK_NSIS_HELP_LINK "${SUPERR_homepage}/issues")
   set(CPACK_NSIS_CONTACT "${SUPERR_homepage}")
endif()

if(WIN32)

   add_subdirectory(win32)

elseif(APPLE)

   add_subdirectory(osx)

elseif(LINUX)

   add_subdirectory(linux)

endif()
