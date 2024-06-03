package main

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestEmbed(t *testing.T) {
	apiKey := os.Getenv("OPENAI_API_KEY")
	assert.NotEmpty(t, apiKey, "set OPENAI_API_KEY")
	client, err := NewAPIClient(apiKey, "")
	assert.NoError(t, err)
	req := &EmbeddingRequest{
		Input: []string{"this is a test", "this is also a test"},
		Model: Text3Small,
	}
	res, err := client.Embed(req)
	assert.NoError(t, err)
	assert.Len(t, res.Data, 2)
	assert.IsType(t, []float64{}, res.Data[0].Embedding)
}
