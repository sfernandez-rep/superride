// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import { safeStorage } from 'electron';
import type { CredentialCodec } from './credential-vault';

/** Fail closed when the OS has no protected credential backend. */
export function electronCredentialCodec(): CredentialCodec {
  const linuxBackend = process.platform === 'linux' ? safeStorage.getSelectedStorageBackend() : '';
  if (!safeStorage.isEncryptionAvailable() ||
      (process.platform === 'linux' && (linuxBackend === 'basic_text' || linuxBackend === 'unknown')))
    throw new Error('Protected system credential storage is unavailable');
  return {
    encrypt: value => safeStorage.encryptString(value),
    decrypt: value => safeStorage.decryptString(value),
  };
}
