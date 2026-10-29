
const process = require("process");

// The webpack dev-server and its multi-logger listen on fixed ports (the
// electron-forge defaults are 3000 and 9000). Allow both to be overridden via
// environment variables so an automated run -- e.g. the Playwright e2e harness,
// which launches its own `npm run start` -- can pick distinct ports and not
// collide with a developer's manually-launched dev instance. Unset leaves the
// option undefined, which the webpack plugin treats as "use the default".
const devServerPort = process.env.RSTUDIO_DESKTOP_DEV_PORT
  ? Number(process.env.RSTUDIO_DESKTOP_DEV_PORT)
  : undefined;
const devLoggerPort = process.env.RSTUDIO_DESKTOP_LOGGER_PORT
  ? Number(process.env.RSTUDIO_DESKTOP_LOGGER_PORT)
  : undefined;

// SUPERR CHANGE: on Windows the desktop is packaged as SuperR, with the
// identity from package/superr/product.json (the build copies this directory
// to src/node/desktop-build-<arch>, so the relative path is the same)
const path = require('path');
const superr = require(path.join(__dirname, '..', '..', '..', 'package', 'superr', 'product.json'));
const superrWindows = process.platform === 'win32';

const config = {
  plugins: [
    {
      name: '@electron-forge/plugin-webpack',
      config: {
        mainConfig: './webpack.main.config.js',
        port: devServerPort,
        loggerPort: devLoggerPort,
        renderer: {
          config: './webpack.renderer.config.js',
          entryPoints: [
            {
              js: './src/renderer/renderer.ts',
              name: 'main_window',
              html: './src/renderer/renderer.html',
              preload: {
                name: 'preload',
                js: './src/renderer/preload.ts',
              },
            },
            {
              html: './src/ui/loading/loading.html',
              js: './src/ui/loading/loading.ts',
              name: 'loading_window',
            },
            {
              html: './src/ui/error/error.html',
              js: './src/ui/error/error.ts',
              name: 'error_window',
            },
            {
              html: './src/ui/connect/connect.html',
              js: './src/ui/connect/connect.ts',
              name: 'connect_window',
            },
            {
              html: './src/ui/widgets/choose-r/ui.html',
              js: './src/ui/widgets/choose-r/load.ts',
              preload: {
                js: './src/ui/widgets/choose-r/preload.ts',
              },
              name: 'choose_r',
            },
            {
              html: './src/ui/splash/splash.html',
              js: './src/ui/splash/splash.ts',
              name: 'splash',
            },
            {
              html: './src/ui/whats-new/whats-new-host.html',
              js: './src/ui/whats-new/whats-new-host.ts',
              preload: {
                js: './src/ui/whats-new/whats-new-preload.ts',
              },
              name: 'whats_new',
            },
          ],
        },
      }
    },
  ],

  // https://electron.github.io/electron-packager/main/interfaces/electronpackager.options.html 
  packagerConfig: superrWindows ? {
    icon: path.join(__dirname, '..', '..', '..', 'assets', 'branding', 'generated', 'superr'),
    appBundleId: superr.bundleId,
    appCopyright: `Copyright (C) 2009-${new Date().getFullYear()} Posit Software, PBC; SuperR changes (C) ${superr.vendor}`,
    name: superr.productName,
    executableName: superr.executableName,
    win32metadata: {
      CompanyName: superr.vendor,
      FileDescription: superr.productName,
      InternalName: superr.productName,
      ProductName: superr.productName,
      OriginalFilename: `${superr.executableName}.exe`,
    },
    extendInfo: './Info.plist',
  } : {
    icon: './resources/icons/RStudio',
    appBundleId: 'com.rstudio.desktop',
    appCopyright: `Copyright (C) ${new Date().getFullYear()} by Posit Software, PBC`,
    name: 'RStudio',
    executableName: process.platform === 'darwin' ? 'RStudio' : 'rstudio',
    win32metadata: {
      CompanyName: "Posit Software, PBC",
      FileDescription: "RStudio",
      InternalName: "RStudio",
      ProductName: "RStudio",
    },
    extendInfo: './Info.plist',
  },
};

module.exports = config;
