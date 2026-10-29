#
# superr-product.cmake
#
# SuperR product identity: reads package/superr/product.json into SUPERR_<key>
# variables (SUPERR_productName, SUPERR_executableName, ...). Included where
# packaging needs the identity (package/, src/node/desktop).
# SPDX-License-Identifier: AGPL-3.0-only
#

file(READ "${CMAKE_CURRENT_LIST_DIR}/product.json" _superr_product_json)
foreach(_key productName executableName version prerelease channel vendor
             description installDirectory registryKey progIdPrefix
             bundleId userFolder homepage notice)
   string(JSON SUPERR_${_key} GET "${_superr_product_json}" ${_key})
endforeach()
set(SUPERR_DISPLAY_VERSION "${SUPERR_version}-${SUPERR_prerelease}")
