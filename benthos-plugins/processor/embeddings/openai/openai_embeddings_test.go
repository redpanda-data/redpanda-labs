package main

import (
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/benthosdev/benthos/v4/public/service"
	"github.com/stretchr/testify/assert"
)

func TestEmbeddingsProcessor(t *testing.T) {
	apiKey := os.Getenv("OPENAI_API_KEY")
	assert.NotEmpty(t, apiKey, "set OPENAI_API_KEY")
	c, err := ConfigSpec.ParseYAML(fmt.Sprintf("api_key: %s", apiKey), nil)
	assert.NoError(t, err)

	embedProc, err := newEmbeddingsProcessor(c, nil, nil)
	assert.NoError(t, err)

	out, err := embedProc.Process(context.Background(), service.NewMessage([]byte(`{"page_content": "this is a test", "metadata": {"source": "testing"}}`)))
	assert.NoError(t, err)
	assert.IsType(t, service.MessageBatch{}, out)
}
