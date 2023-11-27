FROM ghcr.io/webassembly/wasi-sdk:latest

WORKDIR /app
COPY . /app

ENV CFLAGS="$CFLAGS -O2 -mbulk-memory -msimd128 -fno-exceptions -std=c++23 -stdlib=libc++ -Ithird_party/ -static" \
    LDFLAGS="$LDFLAGS -flto -lwasi-emulated-signal -Lthird_party/jq/ -ljq -lonig"

RUN $CXX $CFLAGS $LDFLAGS \
  ./third_party/redpanda/transform_sdk.cc \
  ./transform.cc \
  -o jq.wasm
