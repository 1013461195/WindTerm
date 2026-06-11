#![allow(dead_code)]

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use argon2::{Algorithm, Argon2, Params, Version};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use zeroize::Zeroize;

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum EncryptionAlgorithm {
    Aes256Gcm,
    XChaCha20Poly1305,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CryptoConfig {
    pub algorithm: EncryptionAlgorithm,
    pub memory_cost_kib: u32,
    pub iterations: u32,
    pub parallelism: u32,
}

impl Default for CryptoConfig {
    fn default() -> Self {
        Self {
            algorithm: EncryptionAlgorithm::XChaCha20Poly1305,
            memory_cost_kib: 64 * 1024,
            iterations: 3,
            parallelism: 1,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptedData {
    pub algorithm: EncryptionAlgorithm,
    pub ciphertext: Vec<u8>,
    pub nonce: Vec<u8>,
    pub salt: Vec<u8>,
}

pub struct CredentialEncryptor {
    config: CryptoConfig,
}

impl CredentialEncryptor {
    pub fn new(config: CryptoConfig) -> Self {
        Self { config }
    }

    pub fn encrypt(&self, data: &[u8], password: &[u8]) -> Result<EncryptedData, String> {
        let salt = random_bytes(16);
        let mut key = self.derive_key(password, &salt)?;
        let result = match self.config.algorithm {
            EncryptionAlgorithm::Aes256Gcm => {
                let nonce = random_bytes(12);
                let cipher =
                    Aes256Gcm::new_from_slice(&key).map_err(|_| "无效的 AES 密钥".to_string())?;
                let ciphertext = cipher
                    .encrypt(Nonce::from_slice(&nonce), data)
                    .map_err(|_| "加密失败".to_string())?;
                EncryptedData {
                    algorithm: self.config.algorithm,
                    ciphertext,
                    nonce,
                    salt,
                }
            }
            EncryptionAlgorithm::XChaCha20Poly1305 => {
                let nonce = random_bytes(24);
                let cipher = XChaCha20Poly1305::new_from_slice(&key)
                    .map_err(|_| "无效的 XChaCha20 密钥".to_string())?;
                let ciphertext = cipher
                    .encrypt(XNonce::from_slice(&nonce), data)
                    .map_err(|_| "加密失败".to_string())?;
                EncryptedData {
                    algorithm: self.config.algorithm,
                    ciphertext,
                    nonce,
                    salt,
                }
            }
        };
        key.zeroize();
        Ok(result)
    }

    pub fn decrypt(&self, encrypted: &EncryptedData, password: &[u8]) -> Result<Vec<u8>, String> {
        let mut key = self.derive_key(password, &encrypted.salt)?;
        let result = match encrypted.algorithm {
            EncryptionAlgorithm::Aes256Gcm => {
                if encrypted.nonce.len() != 12 {
                    return Err("无效的 AES nonce".to_string());
                }
                let cipher =
                    Aes256Gcm::new_from_slice(&key).map_err(|_| "无效的 AES 密钥".to_string())?;
                cipher
                    .decrypt(
                        Nonce::from_slice(&encrypted.nonce),
                        encrypted.ciphertext.as_ref(),
                    )
                    .map_err(|_| "解密失败：密码错误或数据已损坏".to_string())
            }
            EncryptionAlgorithm::XChaCha20Poly1305 => {
                if encrypted.nonce.len() != 24 {
                    return Err("无效的 XChaCha20 nonce".to_string());
                }
                let cipher = XChaCha20Poly1305::new_from_slice(&key)
                    .map_err(|_| "无效的 XChaCha20 密钥".to_string())?;
                cipher
                    .decrypt(
                        XNonce::from_slice(&encrypted.nonce),
                        encrypted.ciphertext.as_ref(),
                    )
                    .map_err(|_| "解密失败：密码错误或数据已损坏".to_string())
            }
        };
        key.zeroize();
        result
    }

    fn derive_key(&self, password: &[u8], salt: &[u8]) -> Result<Vec<u8>, String> {
        let params = Params::new(
            self.config.memory_cost_kib,
            self.config.iterations,
            self.config.parallelism,
            Some(32),
        )
        .map_err(|e| format!("无效的 Argon2 参数: {e}"))?;
        let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
        let mut key = vec![0u8; 32];
        argon2
            .hash_password_into(password, salt, &mut key)
            .map_err(|e| format!("密钥派生失败: {e}"))?;
        Ok(key)
    }
}

pub fn secure_zero(data: &mut [u8]) {
    data.zeroize();
}

pub fn random_bytes(len: usize) -> Vec<u8> {
    let mut bytes = vec![0u8; len];
    OsRng.fill_bytes(&mut bytes);
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encrypts_and_authenticates_credentials() {
        let encryptor = CredentialEncryptor::new(CryptoConfig {
            memory_cost_kib: 1024,
            ..CryptoConfig::default()
        });
        let encrypted = encryptor.encrypt(b"secret", b"correct").unwrap();
        assert_ne!(encrypted.ciphertext, b"secret");
        assert_eq!(
            encryptor.decrypt(&encrypted, b"correct").unwrap(),
            b"secret"
        );
        assert!(encryptor.decrypt(&encrypted, b"wrong").is_err());
    }

    #[test]
    fn secure_zero_clears_buffer() {
        let mut secret = *b"secret";
        secure_zero(&mut secret);
        assert_eq!(secret, [0; 6]);
    }
}
