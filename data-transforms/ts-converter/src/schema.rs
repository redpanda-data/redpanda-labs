use anyhow::bail;

pub const MAGIC_BYTES: [u8; 1] = [0x00];

/// Given a slice of bytes, peel off the magic byte and schema id. Returns a tuple
/// of the schema id and a new reference to the remaining data in the slice.
pub fn decompose(buf: &[u8]) -> anyhow::Result<(i32, &[u8])> {
    if !buf.starts_with(&MAGIC_BYTES) {
        bail!("missing magic byte")
    }
    if buf.len() < 5 {
        bail!("frame too short")
    }

    // XXX: Confluent's Python driver decodes as an unsigned int...but I think
    // the actual API uses a signed int. ¯\_(ツ)_/¯
    let id = i32::from_be_bytes([buf[1], buf[2], buf[3], buf[4]]);
    Ok((id, &buf[5..]))
}

#[cfg(test)]
mod tests {
    use crate::schema::{decompose, MAGIC_BYTES};

    #[test]
    fn test_decompose_avro() {
        let good: [u8; 7] = [
            MAGIC_BYTES[0],
            0x00, // 1234, big endian
            0x00,
            0x04,
            0xd2,
            0xbe, // garbage data for now
            0xef,
        ];
        let (id, buf) = decompose(&good).unwrap();
        assert_eq!(1234, id, "should find the schema id");
        assert_eq!([0xbe, 0xef], buf, "should point to actual data");

        let bad_id: [u8; 3] = [MAGIC_BYTES[0], 0x00, 0x00];
        assert!(
            decompose(&bad_id).is_err(),
            "should fail to decompose short id"
        );

        let mut bad_magic = good.clone();
        bad_magic[0] = 0xff;
        assert!(
            decompose(&bad_magic).is_err(),
            "should fail on bad magic byte"
        );
    }
}
