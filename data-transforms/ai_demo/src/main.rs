mod qa;

use qa::*;
use redpanda_transform_sdk::*;
use tract_onnx::tract_core::anyhow::{Context, Result};


fn main() -> Result<()> {
    let content =
        std::env::var("CONTENT").context("required environment variable CONTENT missing")?;

    // TODO: Compress the model + tokenizer with gzip
    let tokenizer_bytes = include_bytes!("../mobilebert/tokenizer.json");
    let model_bytes = include_bytes!("../mobilebert/model.onnx");
    let qa = QuestionAnswerer::new_from_memory(tokenizer_bytes, model_bytes, &content)?;

    redpanda_transform_sdk::on_record_written(|e, w| -> Result<()> {
        let v = match e.record.value() {
            Some(v) => String::from_utf8_lossy(v),
            None => return Ok(()),
        };
        let answer = qa.ask(&v)?;
        let r = Record::new(e.record.key().map(|k| k.to_owned()), answer.map(|s| s.into_bytes()));
        w.write(r)?;
        Ok(())
    })
}
