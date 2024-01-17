This was a demo given during our 23.3 release launch event on January 17th.

An example of exporting a [transformer](https://huggingface.co/docs/transformers/index) model with Python, then loading it into [tract](https://github.com/sonos/tract/) to do question answering via [Extractive QA](https://huggingface.co/tasks/question-answering). This example uses the [MobileBERT model](https://arxiv.org/abs/2004.02984). We load it into [Redpanda](https://redpanda.com) (via WebAssembly!) to show how AI models can be embedded directly into your favorite message broker.

# To Use

First export the pre-trained transformer model using Python and PyTorch.

``` shell
pip3 install transformers torch torchinfo
python3 export.py
```

the exported model and tokenizer are saved in `./mobilebert`. Then build the wasm module for deployment in Redpanda.

``` rust
RUSTFLAGS="-Ctarget-feature=+simd128" cargo build --release --target=wasm32-wasi
```

Enable WebAssembly and tweak configs in the latest build of Redpanda:

```
rpk cluster config set data_transforms_enabled true
# NOTE: These limits allow for a single transform with half a GiB of memory.
rpk cluster config set data_transforms_per_core_memory_reservation 536870912
rpk cluster config set data_transforms_per_function_memory_limit 536870912
# Since we're hackily embedding the model in the Wasm binary, we need to support large binaries.
rpk cluster config set data_transforms_binary_max_size 125829120
# Allow some extra time on startup over the default. This could probably be lower.
rpk cluster config set data_transforms_runtime_limit_ms 30000
# Restart Redpanda!
```

Deploy the model into Redpanda!

``` text
rpk topic create questions answers -r 3
rpk wasm deploy --file ./target/wasm32-wasi/release/ai-qa-wasi.wasm \
  --input-topic questions \
  --output-topic answers \
  --var CONTENT='My name is Bert and I live in the broker.'

echo "What is my name?" | rpk topic produce questions
rpk topic consume answers
```
