use std::path::Path;
use tokenizers::tokenizer::Tokenizer;
use tract_onnx::prelude::*;
use tract_onnx::tract_core::anyhow::{Result, Context, anyhow};

pub struct QuestionAnswerer {
    tokenizer: Tokenizer,
    model: TypedRunnableModel<Graph<TypedFact, Box<dyn TypedOp>>>,
    context: String,
}

#[allow(unused)]
impl QuestionAnswerer {

    pub fn new_from_disk(
        tokenizer_file: impl AsRef<Path>,
        model_file: impl AsRef<Path>,
        content: impl Into<String>,
    ) -> Result<Self> {
        let tokenizer = Tokenizer::from_file(tokenizer_file).map_err(|e| anyhow!(e))?;
        let model =
            tract_onnx::onnx().model_for_path(model_file)?.into_optimized()?.into_runnable()?;
        let context = content.into();
        Ok(Self { tokenizer, model, context })
    }

    pub fn new_from_memory(
        tokenizer_file: impl AsRef<[u8]>,
        model_file: impl AsRef<[u8]>,
        content: impl Into<String>,
    ) -> Result<Self> {
        let tokenizer = Tokenizer::from_bytes(tokenizer_file).map_err(|e| anyhow!(e))?;
        let model = tract_onnx::onnx()
            .model_for_read(&mut model_file.as_ref())?
            .into_optimized()?
            .into_runnable()?;
        let context = content.into();
        Ok(Self { tokenizer, model, context })
    }

    pub fn ask(&self, question: &str) -> Result<Option<String>> {
        let tokenizer_output = self.tokenizer.encode((question, self.context.as_str()), true).map_err(|e| anyhow!(e))?;
        let input_ids = tokenizer_output.get_ids();
        let attention_mask = tokenizer_output.get_attention_mask();
        let token_type_ids = tokenizer_output.get_type_ids();
        let length = input_ids.len();

        let input_ids: Tensor = tract_ndarray::Array2::from_shape_vec(
            (1, length),
            input_ids.iter().map(|&x| x as i64).collect(),
        )?
        .into();
        let attention_mask: Tensor = tract_ndarray::Array2::from_shape_vec(
            (1, length),
            attention_mask.iter().map(|&x| x as i64).collect(),
        )?
        .into();
        let token_type_ids: Tensor = tract_ndarray::Array2::from_shape_vec(
            (1, length),
            token_type_ids.iter().map(|&x| x as i64).collect(),
        )?
        .into();

        let outputs = self.model.run(tvec!(
            input_ids.into(),
            attention_mask.into(),
            token_type_ids.into()
        ))?;

        let start_logits = outputs[0].to_array_view::<f32>()?;
        let start_logits = start_logits.as_slice().context("incorrect type for start_logits")?;

        let end_logits = outputs[1].to_array_view::<f32>()?;
        let end_logits = end_logits.as_slice().context("incorrect type for end_logits")?;

        if let (Some(answer_start), Some(answer_end)) = (argmax(start_logits), argmax(end_logits)) {
            let (range_start, _) = &tokenizer_output.get_offsets()[answer_start];
            let (_, range_end) = &tokenizer_output.get_offsets()[answer_end];
            Ok(Some(self.context[*range_start..*range_end].to_string()))
        } else {
            Ok(None)
        }
    }
}

fn argmax(v: &[f32]) -> Option<usize> {
    v.iter().enumerate().max_by(|(_, a), (_, b)| a.total_cmp(b)).map(|(idx, _)| idx)
}

