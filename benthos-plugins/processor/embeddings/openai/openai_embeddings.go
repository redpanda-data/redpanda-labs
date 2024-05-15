package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/benthosdev/benthos/v4/public/service"
)

var ConfigSpec = service.NewConfigSpec().
	Summary("Processor that uses the OpenAI API to create vector embeddings for RAG applications.").
	Field(service.NewStringField("api_key")).
	Field(service.NewStringField("org_id").Default("")).
	Field(service.NewStringField("model").Default(Text3Small.String()))

func getValue(conf *service.ParsedConfig, key string) string {
	v, err := conf.FieldString(key)
	if err != nil {
		panic(fmt.Sprintf("missing config: %s", key))
	}
	return v
}

func init() {
	constructor := func(conf *service.ParsedConfig, mgr *service.Resources) (service.Processor, error) {
		return newEmbeddingsProcessor(conf, mgr.Logger(), mgr.Metrics())
	}
	err := service.RegisterProcessor("openai_embeddings", ConfigSpec, constructor)
	if err != nil {
		panic(err)
	}
}

func newEmbeddingsProcessor(conf *service.ParsedConfig, logger *service.Logger, metrics *service.Metrics) (*embeddingsProcessor, error) {
	client, err := NewAPIClient(getValue(conf, "api_key"), getValue(conf, "org_id"))
	if err != nil {
		return nil, err
	}
	m := Model(getValue(conf, "model"))
	logger.Debugf("url: %s, model: %s", client.URL.String(), m.String())
	return &embeddingsProcessor{
		logger:       logger,
		promptTokens: metrics.NewCounter("prompt_tokens"),
		totalTokens:  metrics.NewCounter("total_tokens"),
		apiClient:    client,
		model:        m,
	}, nil
}

type embeddingsProcessor struct {
	logger *service.Logger
	// Keep track of OpenAI API token usage
	promptTokens *service.MetricCounter
	totalTokens  *service.MetricCounter
	apiClient    *APIClient
	model        Model
}

type Document struct {
	Text      string                 `json:"page_content"`
	Metadata  map[string]interface{} `json:"metadata"`
	Embedding []float64              `json:"embedding"`
}

func (e *embeddingsProcessor) Process(ctx context.Context, m *service.Message) (service.MessageBatch, error) {
	bytes, err := m.AsBytes()
	if err != nil {
		return nil, err
	}

	result := Document{}
	if err := json.Unmarshal(bytes, &result); err != nil {
		// message can be a string (it does not have to be in json format)
		e.logger.Error(fmt.Sprintf("document unmarshal error: %v", err))
		result.Text = string(bytes)
		result.Metadata = make(map[string]interface{})
	}
	e.logger.Debugf("received document with text: %s", result.Text)

	if _, ok := result.Metadata["document_id"]; !ok {
		// add id to uniquely identify the document
		h := sha256.New()
		h.Write([]byte(result.Text))
		result.Metadata["document_id"] = h.Sum(nil)
	}

	req := &EmbeddingRequest{
		Input: result.Text,
		Model: e.model,
	}
	resp, err := e.apiClient.Embed(req)
	if err != nil {
		return nil, err
	}
	if len(resp.Data) == 0 {
		return nil, errors.New("zero embeddings in response")
	}
	if len(resp.Data) > 1 {
		return nil, errors.New("unexpected number of embeddings in response")
	}
	result.Embedding = resp.Data[0].Embedding

	// increment token counters
	e.promptTokens.Incr(int64(resp.Usage.PromptTokens))
	e.totalTokens.Incr(int64(resp.Usage.TotalTokens))

	b, err := json.Marshal(result)
	if err != nil {
		return nil, err
	}
	m.SetBytes(b)
	return []*service.Message{m}, nil
}

func (r *embeddingsProcessor) Close(ctx context.Context) error {
	return nil
}
