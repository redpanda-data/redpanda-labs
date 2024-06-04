package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

const (
	BaseURL   = "https://api.openai.com/v1/embeddings"
	OrgHeader = "OpenAI-Organization"
)

type APIClient struct {
	URL        url.URL
	APIKey     string
	Org        string
	HTTPClient *http.Client
}

// ----- OpenAI Embeddings API -----
// https://platform.openai.com/docs/guides/embeddings

type Data struct {
	Object    string    `json:"object"`
	Index     int       `json:"index"`
	Embedding []float64 `json:"embedding"`
}

type Model string

const (
	Text3Small Model = "text-embedding-3-small"
	Text3Large Model = "text-embedding-3-large"
	TextAda002 Model = "text-embedding-ada-002"
)

func (m Model) String() string {
	return string(m)
}

type Usage struct {
	PromptTokens int `json:"prompt_tokens"`
	TotalTokens  int `json:"total_tokens"`
}

// Use default encoding_format of "float"
type EmbeddingRequest struct {
	Input any   `json:"input"`
	Model Model `json:"model"`
}

type EmbeddingResponse struct {
	Object string `json:"object"`
	Data   []Data `json:"data"`
	Model  Model  `json:"model"`
	Usage  Usage  `json:"usage"`
}

// ---------------------------------

func NewAPIClient(key string, org string) (*APIClient, error) {
	u, err := url.Parse(BaseURL)
	if err != nil {
		return nil, err
	}
	return &APIClient{
		URL:        *u,
		APIKey:     key,
		Org:        org,
		HTTPClient: &http.Client{Timeout: 2 * time.Second},
	}, nil
}

func (c *APIClient) Embed(r *EmbeddingRequest) (*EmbeddingResponse, error) {
	var body = &bytes.Buffer{}
	encoder := json.NewEncoder(body)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(r); err != nil {
		return nil, err
	}

	req, err := http.NewRequest(http.MethodPost, c.URL.String(), body)
	if err != nil {
		return nil, err
	}
	req.Header.Add("Content-Type", "application/json")
	req.Header.Add("Authorization", fmt.Sprintf("Bearer %s", c.APIKey))
	if c.Org != "" {
		req.Header.Add(OrgHeader, c.Org)
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	er := &EmbeddingResponse{}
	if err := json.NewDecoder(resp.Body).Decode(er); err != nil {
		fmt.Println(err)
		return nil, err
	}
	return er, nil
}
