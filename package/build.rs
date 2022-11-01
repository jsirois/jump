use std::env;
use std::path::PathBuf;

use byteorder::{LittleEndian, WriteBytesExt};
use jump::EOF_MAGIC;

const SCIE_JUMP_BINARY: &str = "scie-jump";

fn main() -> Result<(), String> {
    let bindep_env_var = format!("CARGO_BIN_FILE_SCIE_JUMP_{SCIE_JUMP_BINARY}");
    let path: PathBuf = std::env::var_os(&bindep_env_var)
        .ok_or_else(|| format!("The {bindep_env_var} environment variable was not set."))?
        .into();

    let size = u32::try_from(
        path.metadata()
            .map_err(|e| format!("Failed to find size of {path}: {e}", path = &path.display()))?
            .len(),
    )
    .map_err(|e| format!("{e}"))?;

    let mut binary = std::fs::OpenOptions::new()
        .append(true)
        .open(&path)
        .map_err(|e| format!("{e}"))?;

    binary
        .write_u32::<LittleEndian>(size + 8)
        .and_then(|()| binary.write_u32::<LittleEndian>(EOF_MAGIC))
        .map_err(|e| format!("{e}"))?;

    let dest = std::env::var("OUT_DIR")
        .map(|path| {
            PathBuf::from(path)
                .join(format!(
                    "{SCIE_JUMP_BINARY}-{os}-{arch}",
                    os = env::consts::OS,
                    arch = env::consts::ARCH
                ))
                .with_extension(env::consts::EXE_EXTENSION)
        })
        .map_err(|e| format!("{e}"))?;
    std::fs::copy(path, &dest).map_err(|e| format!("{e}"))?;
    println!("cargo:rustc-env=SCIE_STRAP={}", dest.display());
    println!("cargo:warning=Packaged scie-jump to {}", dest.display());
    Ok(())
}
