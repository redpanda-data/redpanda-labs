package redactors

import (
	"errors"
	"fmt"
	"github.com/pmw-rp/jsonparser"
	"gopkg.in/yaml.v3"
	"redactor/functions"
	"strings"
)

func wrap(message string, err error) error {
	return errors.Join(errors.New(message), err)
}

type Config struct {
	Redactors  []RedactorConf `yaml:"redactors"`
	Redactions []Redaction    `yaml:"redactions"`
}

type RedactorConf struct {
	Name  string         `yaml:"name"`
	Type  string         `yaml:"type"`
	Quote bool           `yaml:"quote"`
	Key   map[string]any `yaml:"key"`
	Value map[string]any `yaml:"value"`
}

type Redaction struct {
	Path      string `yaml:"path"`
	PathSlice []string
	Type      string `yaml:"type"`
	Redactor  Redactor
}

func (r Redaction) apply(data []byte) ([]*jsonparser.Delta, error) {
	if len(r.PathSlice) == 0 {
		r.PathSlice = strings.Split(r.Path, ".")
	}
	return r.Redactor.process(data, r.PathSlice...)
}

var redactors *map[string]Redactor
var redactions []Redaction

func Clear() {
	redactors = nil
	redactions = nil
}

func Configure(bytes []byte) error {
	if redactors == nil {
		r := make(map[string]Redactor)
		redactors = &r
	}
	if redactions == nil {
		redactions = []Redaction{}
	}
	config := &Config{Redactors: make([]RedactorConf, 0), Redactions: []Redaction{}}
	err := yaml.Unmarshal(bytes, config)
	if err != nil {
		return wrap("unable to unmarshall config", err)
	}
	err = buildRedactors(*config)
	if err != nil {
		return wrap("unable to build redactors", err)
	}
	for _, redaction := range config.Redactions {
		if redaction.Type != "drop" && (*redactors)[redaction.Type] == nil {
			return errors.New(fmt.Sprintf("redactor is nil for redaction (path %s, type %s)", redaction.Path, redaction.Type))
		}
		redaction.Redactor = (*redactors)[redaction.Type]
		redactions = append(redactions, redaction)
	}
	return nil
}

func buildRedactor(conf RedactorConf) (Redactor, error) {
	switch conf.Type {
	case "drop":
		return DropRedactor{}, nil
	case "value":
		valueFn, err := functions.BuildFunction(conf.Value)
		if err != nil {
			return nil, err
		}
		return ValueRedactor{quote: conf.Quote, valueFn: valueFn}, nil
	case "key-value":
		keyFn, err := functions.BuildFunction(conf.Key)
		if err != nil {
			return nil, err
		}
		valueFn, err := functions.BuildFunction(conf.Value)
		if err != nil {
			return nil, err
		}
		return KeyValueRedactor{quote: conf.Quote, keyFn: keyFn, valueFn: valueFn}, nil
	}

	return nil, errors.New("unable to make redactor")
}

func buildRedactors(config Config) error {
	for _, conf := range config.Redactors {
		redactor, err := buildRedactor(conf)
		if err != nil {
			return err
		}
		(*redactors)[conf.Name] = redactor
	}
	return nil
}

type Redactor interface {
	process(data []byte, path ...string) ([]*jsonparser.Delta, error)
}

func Process(data []byte) ([]byte, error) {
	var deltas []*jsonparser.Delta
	for _, redaction := range redactions {
		extraDeltas, err := redaction.apply(data)
		if err != nil {
			return data[:0], err
		}
		deltas = append(deltas, extraDeltas...)
	}
	result, err := jsonparser.Apply(deltas, data)
	if err != nil {
		return data[:0], err
	}
	return result, nil
}

/////////

type ValueRedactor struct {
	quote   bool
	valueFn func([]byte) ([]byte, error)
}

func (f ValueRedactor) process(data []byte, path ...string) ([]*jsonparser.Delta, error) {
	//key := path[len(path) - 1]
	value, typ, offset, err := jsonparser.Get(data, path...)
	if err != nil {
		return nil, err
	}
	_ = typ
	_ = offset
	transformedValue, err := f.valueFn(value)
	if f.quote {
		transformedValue = []byte("\"" + string(transformedValue) + "\"")
	}
	if err != nil {
		return nil, err
	}
	delta, err := jsonparser.SetDelta(data, transformedValue, path...)
	if err != nil {
		return nil, err
	}
	return []*jsonparser.Delta{delta}, nil
}

/////////

type DropRedactor struct{}

func (f DropRedactor) process(data []byte, path ...string) ([]*jsonparser.Delta, error) {
	return []*jsonparser.Delta{jsonparser.DeleteDelta(data, path...)}, nil
}

/////////

type KeyValueRedactor struct {
	quote   bool
	keyFn   func([]byte) ([]byte, error)
	valueFn func([]byte) ([]byte, error)
}

func (f KeyValueRedactor) process(data []byte, path ...string) ([]*jsonparser.Delta, error) {
	key := path[len(path)-1]
	value, typ, offset, err := jsonparser.Get(data, path...)
	if err != nil {
		return nil, err
	}
	_ = typ
	_ = offset
	transformedValue, err := f.valueFn(value)
	if f.quote {
		transformedValue = []byte("\"" + string(transformedValue) + "\"")
	}
	if err != nil {
		return nil, err
	}
	transformedKey, err := f.keyFn([]byte(key))
	if err != nil {
		return nil, err
	}
	var newPath []string
	newPath = append(newPath, path[0:len(path)-1]...)
	newPath = append(newPath, string(transformedKey))
	newKeyAndValueDelta, err := jsonparser.SetDelta(data, transformedValue, newPath...)
	if err != nil {
		return nil, err
	}
	deletionDelta := jsonparser.DeleteDelta(data, path...)
	return []*jsonparser.Delta{deletionDelta, newKeyAndValueDelta}, nil
}
