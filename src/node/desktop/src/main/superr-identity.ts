/*
 * superr-identity.ts
 *
 * Copyright (C) 2026 by SuperR contributors
 *
 * This program is licensed to you under the terms of version 3 of the
 * GNU Affero General Public License. This program is distributed WITHOUT
 * ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING THOSE OF NON-INFRINGEMENT,
 * MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE. Please refer to the
 * AGPL (http://www.gnu.org/licenses/agpl-3.0.txt) for more details.
 *
 */

import { app } from 'electron';
import os from 'os';
import path from 'path';
import { getenv, setenv } from '../core/environment';

// Must match package/superr/product.json (productName, userFolder);
// tools/superrstudio/check-identity.ps1 verifies it.
export const kSuperRProductName = 'SuperR';
export const kSuperRUserFolder = 'SuperR';

/**
 * @returns true in the packaged Windows SuperR application (not in
 *   development runs, which start Electron on the build directory)
 */
export function isSuperRPackage(): boolean {
  return process.platform === 'win32' && app.isPackaged && app.name === kSuperRProductName;
}

/**
 * Gives the packaged SuperR application settings and session state of its
 * own, so it runs beside RStudio without reading or changing RStudio's
 * preferences: %APPDATA%\SuperR and %LOCALAPPDATA%\SuperR instead of the
 * RStudio folders. R itself is still discovered as RStudio does. Variables
 * already set by the user are respected. Runs before anything reads the
 * user directories; the R session inherits the environment.
 */
export function applySuperRIdentity(): void {
  if (!isSuperRPackage()) {
    return;
  }
  if (!getenv('RSTUDIO_CONFIG_HOME')) {
    setenv('RSTUDIO_CONFIG_HOME', path.join(app.getPath('appData'), kSuperRUserFolder));
  }
  if (!getenv('RSTUDIO_DATA_HOME')) {
    const localAppData = getenv('LOCALAPPDATA') || path.join(os.homedir(), 'AppData', 'Local');
    setenv('RSTUDIO_DATA_HOME', path.join(localAppData, kSuperRUserFolder));
  }
  // the SuperR features are on in the packaged application;
  // SUPER_RSTUDIO_EXPERIMENTAL=0 starts it with them off
  if (!getenv('SUPER_RSTUDIO_EXPERIMENTAL')) {
    setenv('SUPER_RSTUDIO_EXPERIMENTAL', '1');
  }
}
