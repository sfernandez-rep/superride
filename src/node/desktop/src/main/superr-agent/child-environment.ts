// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only

/** Avoid forwarding unrelated API keys and research-session variables to agents. */
export function childEnvironment(source: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  const allow = new Set(['PATH', 'PATHEXT', 'SYSTEMROOT', 'WINDIR', 'COMSPEC',
    'HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR',
    'LANG', 'LC_ALL', 'LC_CTYPE', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME',
    'SSL_CERT_FILE', 'SSL_CERT_DIR', 'HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY']);
  for (const [key, value] of Object.entries(source))
    if (allow.has(key.toUpperCase()) && value !== undefined) env[key] = value;
  return env;
}
