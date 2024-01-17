# -*- coding: utf-8 -*-

import os

import torchinfo
import torch
from transformers import AutoModelForQuestionAnswering, AutoTokenizer

model_name = "csarron/mobilebert-uncased-squad-v2"

tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForQuestionAnswering.from_pretrained(model_name)

question = "What's my name?"
text = """My name is Clara and I live in Berkeley."""

tokenizer_output = tokenizer.encode_plus(question, text, max_length=128, padding='max_length', return_tensors="pt")

input_ids = tokenizer_output["input_ids"]
attention_mask = tokenizer_output["attention_mask"]
token_type_ids = tokenizer_output["token_type_ids"]
print(tokenizer_output)
torchinfo.summary(model, input_data=[input_ids, attention_mask, token_type_ids])

outputs = model(input_ids=input_ids, attention_mask=attention_mask, token_type_ids=token_type_ids)
print(outputs)
print(outputs.start_logits, outputs.end_logits)
answer_start = torch.argmax(outputs.start_logits)
answer_end = torch.argmax(outputs.end_logits) + 1
span_score = torch.max(outputs.start_logits) + torch.max(outputs.end_logits)
print(                "range", answer_start,answer_end)
print(                "tokens", input_ids[0][answer_start:answer_end])
print(
        tokenizer.convert_tokens_to_string(
            tokenizer.convert_ids_to_tokens(
                input_ids[0][answer_start:answer_end])))


output_dir = "./mobilebert"
os.makedirs(output_dir, exist_ok=True)
torch.onnx.export(
    model,
    (input_ids, attention_mask, token_type_ids),
    os.path.join(output_dir, "model.onnx"),
    input_names=["input_ids", "attention_mask", "token_type_ids"],
    output_names=["start_logits", "end_logits"],
    opset_version=17,
)

tokenizer.save_pretrained(output_dir)
