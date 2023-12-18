package redactors

import (
	"errors"
	"gopkg.in/yaml.v3"
	"redactor/functions"
	"reflect"
)

func wrap(message string, err error) error {
	return errors.Join(errors.New(message), err)
}

type Config struct {
	Redactors  []RedactorConf `yaml:"redactors"`
	Redactions map[string]string
}

type RedactorConf struct {
	Name  string         `yaml:"name"`
	Type  string         `yaml:"type"`
	Key   map[string]any `yaml:"key"`
	Value map[string]any `yaml:"value"`
}

var redactors map[string]Redactor
var redactions map[string]Redactor

func Clear() {
	redactors = nil
	redactions = nil
}

func Configure(bytes []byte) error {
	if redactors == nil {
		redactors = make(map[string]Redactor)
	}
	if redactions == nil {
		redactions = make(map[string]Redactor)
	}
	config := &Config{Redactors: make([]RedactorConf, 0), Redactions: make(map[string]string)}
	err := yaml.Unmarshal(bytes, config)
	if err != nil {
		return wrap("unable to unmarshall config", err)
	}
	err = buildRedactors(*config)
	if err != nil {
		return wrap("unable to build redactors", err)
	}
	for k, v := range config.Redactions {
		_, ok := redactors[v]
		if !ok {
			return errors.New("no such redactor: " + v)
		} else {
			redactions[k] = redactors[v]
		}
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
		return ValueRedactor{valueFn: valueFn}, nil
	case "both":
		keyFn, err := functions.BuildFunction(conf.Key)
		if err != nil {
			return nil, err
		}
		valueFn, err := functions.BuildFunction(conf.Value)
		if err != nil {
			return nil, err
		}
		return KeyValueRedactor{keyFn: keyFn, valueFn: valueFn}, nil
	}

	return nil, errors.New("unable to make redactor")
}

func buildRedactors(config Config) error {
	for _, conf := range config.Redactors {
		redactor, err := buildRedactor(conf)
		if err != nil {
			return err
		}
		redactors[conf.Name] = redactor
	}
	return nil
}

type Tracker struct {
	data      map[string]any
	additions map[string]any
	deletions map[string]bool
	key       string
	value     any
}

func NewRedactionTracker(data map[string]any) Tracker {
	return Tracker{data: data, additions: make(map[string]any), deletions: make(map[string]bool), key: ""}
}

func (rt *Tracker) process() error {
	for k, v := range rt.data {
		fn, ok := redactions[k]
		if ok && isABasicType(v) {
			rt.key = k
			rt.value = v
			err := fn.redact(rt)
			if err != nil {
				return err
			}
		} else if isAMap(v) {
			subMap := v.(map[string]any)
			tracker := NewRedactionTracker(subMap)
			err := tracker.process()
			if err != nil {
				return err
			}
		} else if isAnArray(v) {
			subArray := v.([]any)
			for _, item := range subArray {
				if isAMap(item) {
					subMap := item.(map[string]any)
					tracker := NewRedactionTracker(subMap)
					err := tracker.process()
					if err != nil {
						return err
					}
				}
			}
		}
	}
	for k := range rt.deletions {
		delete(rt.data, k)
	}
	for k, v := range rt.additions {
		rt.data[k] = v
	}
	return nil
}

func (rt *Tracker) add(key string, value any) {
	rt.additions[key] = value
}

func (rt *Tracker) drop() {
	rt.deletions[rt.key] = true
}

func (rt *Tracker) getKey() string {
	return rt.key
}

func (rt *Tracker) getValue() any {
	return rt.value
}

func (rt *Tracker) setValue(value any) {
	rt.data[rt.key] = value
}

type Redactor interface {
	redact(api RedactorApi) error
}

func Process(data map[string]any) error {
	tracker := NewRedactionTracker(data)
	return tracker.process()
}

/////////

var basicTypes = map[string]bool{
	"string":     true,
	"bool":       true,
	"float32":    true,
	"float64":    true,
	"rune":       true,
	"byte":       true,
	"complex64":  true,
	"complex128": true,
	"int":        true,
	"int8":       true,
	"int16":      true,
	"int32":      true,
	"int64":      true,
	"uint":       true,
	"uint8":      true,
	"uint16":     true,
	"uint32":     true,
	"uint64":     true,
	"uintptr":    true,
}

func isABasicType(a any) bool {
	t := reflect.TypeOf(a).String()
	_, ok := basicTypes[t]
	return ok
}

func isAMap(a any) bool {
	_, ok := a.(map[string]any)
	return ok
}

func isAnArray(a any) bool {
	_, ok := a.([]any)
	return ok
}

/////////

type ValueRedactor struct {
	valueFn func(any) (any, error)
}

func (f ValueRedactor) redact(api RedactorApi) error {
	value, err := f.valueFn(api.getValue())
	if err != nil {
		return err
	}
	api.setValue(value)
	return nil
}

/////////

type DropRedactor struct{}

func (f DropRedactor) redact(api RedactorApi) error {
	api.drop()
	return nil
}

/////////

type KeyValueRedactor struct {
	keyFn   func(any) (any, error)
	valueFn func(any) (any, error)
}

func (f KeyValueRedactor) redact(api RedactorApi) error {
	key, err := f.keyFn(api.getKey())
	if err != nil {
		return err
	}
	value, err := f.valueFn(api.getValue())
	if err != nil {
		return err
	}
	api.drop()
	api.add(key.(string), value)
	return nil
}
