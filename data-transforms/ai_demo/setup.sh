# Install python deps and export our model.
pip3 install transformers torch torchinfo
python3 export.py
# Build it!
RUSTFLAGS="-Ctarget-feature=+simd128" cargo build --release --target=wasm32-wasi
# Deploy to our locally running container
rpk container start
# Modify the required cluster configurations
rpk cluster config set data_transforms_enabled true
# NOTE: These limits allow for a single transform with half a GiB of memory.
rpk cluster config set data_transforms_per_core_memory_reservation 536870912
rpk cluster config set data_transforms_per_function_memory_limit 536870912
# Since we're hackily embedding the model in the Wasm binary, we need to support large binaries.
rpk cluster config set data_transforms_binary_max_size 125829120
# Allow some extra time on startup over the default. This could probably be lower.
rpk cluster config set data_transforms_runtime_limit_ms 30000
# Retart our node.
rpk container stop
rpk container start
# Create needed topics
rpk topic create questions answers
cp ./target/wasm32-wasi/release/ai-qa-wasi.wasm .
rpk wasm deploy
