package redactors

import (
	"errors"
	"fmt"
	"gopkg.in/yaml.v3"
	"strconv"
	"strings"
)

type Config struct {
	Redactors  []Redactor        `yaml:"redactors"`
	Redactions map[string]string `yaml:"redactions"`
}

type Redactor struct {
	Name   string         `yaml:"name"`
	Config map[string]any `yaml:"config"`
}

func GetConfig(bytes []byte) (*Config, error) {
	config := &Config{}
	err := yaml.Unmarshal(bytes, config)
	if err != nil {
		return nil, err
	}
	return config, nil
}

func buildFunction(config map[string]any) (func(any) (any, error), error) {
	fn := config["function"]
	switch fn {
	case "replace":
		replacement := config["replacement"].(string)
		return func(input any) (any, error) {
			return replace(input.(string), replacement)
		}, nil
	case "replaceBeforeSeparator":
		replacement := config["replacement"].(string)
		separator := config["separator"].(string)
		return func(input any) (any, error) {
			return replaceBeforeSeparator(input.(string), replacement, separator)
		}, nil
	case "truncateFloat64":
		decimals := config["decimals"].(int)
		return func(input any) (any, error) {
			return truncateFloat64(input.(float64), decimals)
		}, nil
	default:
		return nil, errors.New("unable to create redaction function from config")
	}
}

func GetRedactors(config Config) (map[string]func(any) (any, error), error) {
	redactors := make(map[string]func(any) (any, error))
	for _, redactor := range config.Redactors {
		fn, err := buildFunction(redactor.Config)
		if err != nil {
			return nil, err
		}
		redactors[redactor.Name] = fn
	}
	return redactors, nil
}

func replace(input string, replacement string) (string, error) {
	return replacement, nil
}

func replaceBeforeSeparator(input string, replacement string, separator string) (string, error) {
	if !strings.Contains(input, separator) {
		return "", errors.New(fmt.Sprintf("input string \"%s\" doesn't contain separator \"%s\"", input, separator))
	}
	split := strings.Split(input, separator)
	if len(split) != 2 {
		return "", errors.New(fmt.Sprintf("input string \"%s\" contains multiple separators \"%s\"", input, separator))
	}
	return replacement + separator + split[1], nil
}

func truncateFloat64(input float64, decimals int) (float64, error) {
	format := "%." + strconv.Itoa(decimals) + "f"
	s := fmt.Sprintf(format, input)
	return strconv.ParseFloat(s, 64)
}
