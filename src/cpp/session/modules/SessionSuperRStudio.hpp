// SuperRStudio experimental visual workflow. SPDX-License-Identifier: AGPL-3.0-only
#ifndef SESSION_SUPER_RSTUDIO_HPP
#define SESSION_SUPER_RSTUDIO_HPP
#include <shared_core/Error.hpp>
namespace rstudio { namespace session { namespace modules { namespace superrstudio {
core::Error initialize();
// SUPER_RSTUDIO_EXPERIMENTAL=1: SuperRStudio features (reported to the client at init)
bool enabled();
}}}}
#endif
