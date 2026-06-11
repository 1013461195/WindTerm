use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use sha2::{Digest, Sha256};
use std::io::Read;

pub fn verify_signature(payload: &[u8], signature_b64: &str, public_key_b64: &str) -> bool {
    let Ok(public_key) = BASE64.decode(public_key_b64) else {
        return false;
    };
    let Ok(public_key) = <[u8; 32]>::try_from(public_key) else {
        return false;
    };
    let Ok(verifying_key) = VerifyingKey::from_bytes(&public_key) else {
        return false;
    };
    let Ok(signature) = BASE64.decode(signature_b64) else {
        return false;
    };
    let Ok(signature) = Signature::from_slice(&signature) else {
        return false;
    };
    verifying_key.verify(payload, &signature).is_ok()
}

pub fn verify_sha256(data: &[u8], expected_hex: &str) -> bool {
    let digest = Sha256::digest(data);
    format!("{digest:x}").eq_ignore_ascii_case(expected_hex.trim())
}

pub fn verify_file_sha256(path: &str, expected_hex: &str) -> bool {
    let Ok(mut file) = std::fs::File::open(path) else {
        return false;
    };
    let mut digest = Sha256::new();
    let mut buffer = [0u8; 256 * 1024];
    loop {
        let Ok(read) = file.read(&mut buffer) else {
            return false;
        };
        if read == 0 {
            break;
        }
        digest.update(&buffer[..read]);
    }
    format!("{:x}", digest.finalize()).eq_ignore_ascii_case(expected_hex.trim())
}

#[cfg(test)]
mod tests {
    use super::{verify_sha256, verify_signature};
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
    use ed25519_dalek::{Signer, SigningKey};

    #[test]
    fn verifies_signed_update_payload() {
        let signing_key = SigningKey::from_bytes(&[7u8; 32]);
        let payload = br#"{"version":"1.2.3"}"#;
        let signature = signing_key.sign(payload);
        assert!(verify_signature(
            payload,
            &BASE64.encode(signature.to_bytes()),
            &BASE64.encode(signing_key.verifying_key().to_bytes()),
        ));
        assert!(!verify_signature(
            b"changed",
            &BASE64.encode(signature.to_bytes()),
            &BASE64.encode(signing_key.verifying_key().to_bytes()),
        ));
    }

    #[test]
    fn verifies_package_digest() {
        assert!(verify_sha256(
            b"wind-send",
            "be6995cb5a0c1c4cbe4eb6c9da33b86163787c3a0705f9a6e9385e93eb46bcd2",
        ));
    }
}
