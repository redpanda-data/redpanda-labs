package functions

import (
	"crypto/md5"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"reflect"
	"strconv"
	"strings"
)

func validateConfig(config map[string]any, requirements map[string]reflect.Kind) error {
	var errorSlice []error
	for key, kind := range requirements {
		_, ok := config[key]
		if !ok {
			errorSlice = append(errorSlice, errors.New(fmt.Sprintf("required config parameter %s doesn't exist", key)))
		} else {
			if reflect.ValueOf(config[key]).Kind() != kind {
				errorSlice = append(errorSlice, errors.New(fmt.Sprintf("required config parameter %s has the wrong kind: expected %v", key, kind)))
			}
		}
	}
	return errors.Join(errorSlice...)
}

func validateValue(v any, kind reflect.Kind) error {
	if reflect.ValueOf(v).Kind() != kind {
		return errors.New(fmt.Sprintf("parameter %v has the wrong kind: expected %v", v, kind))
	} else {
		return nil
	}
}

func BuildFunction(config map[string]any) (func(any) (any, error), error) {
	fn := config["function"]
	switch fn {
	case "replace":
		err := validateConfig(config, map[string]reflect.Kind{"replacement": reflect.String})
		if err != nil {
			return nil, err
		}
		replacement := config["replacement"].(string)
		return func(input any) (any, error) {
			err := validateValue(input, reflect.String)
			if err != nil {
				return nil, err
			}
			return replace(input.(string), replacement)
		}, nil
	case "replaceBeforeSeparator":
		err := validateConfig(config, map[string]reflect.Kind{"replacement": reflect.String, "separator": reflect.String})
		if err != nil {
			return nil, err
		}
		replacement := config["replacement"].(string)
		separator := config["separator"].(string)
		return func(input any) (any, error) {
			err := validateValue(input, reflect.String)
			if err != nil {
				return nil, err
			}
			return replaceBeforeSeparator(input.(string), replacement, separator)
		}, nil
	case "truncateFloat64":
		err := validateConfig(config, map[string]reflect.Kind{"decimals": reflect.Int})
		if err != nil {
			return nil, err
		}
		decimals := config["decimals"].(int)
		return func(input any) (any, error) {
			err := validateValue(input, reflect.Float64)
			if err != nil {
				return nil, err
			}
			return truncateFloat64(input.(float64), decimals)
		}, nil
	case "md5":
		return func(input any) (any, error) {
			err := validateValue(input, reflect.String)
			if err != nil {
				return nil, err
			}
			return hashWithMD5(input.(string))
		}, nil
	case "sha1":
		return func(input any) (any, error) {
			err := validateValue(input, reflect.String)
			if err != nil {
				return nil, err
			}
			return hashWithSHA1(input.(string))
		}, nil
	case "prepend":
		err := validateConfig(config, map[string]reflect.Kind{"prefix": reflect.String})
		if err != nil {
			return nil, err
		}
		prefix := config["prefix"].(string)
		return func(input any) (any, error) {
			err := validateValue(input, reflect.String)
			if err != nil {
				return nil, err
			}
			return prepend(input.(string), prefix)
		}, nil
	case "camelPrepend":
		err := validateConfig(config, map[string]reflect.Kind{"prefix": reflect.String})
		if err != nil {
			return nil, err
		}
		prefix := config["prefix"].(string)
		return func(input any) (any, error) {
			err := validateValue(input, reflect.String)
			if err != nil {
				return nil, err
			}
			return camelPrepend(input.(string), prefix)
		}, nil
	case "append":
		err := validateConfig(config, map[string]reflect.Kind{"suffix": reflect.String})
		if err != nil {
			return nil, err
		}
		suffix := config["suffix"].(string)
		return func(input any) (any, error) {
			err := validateValue(input, reflect.String)
			if err != nil {
				return nil, err
			}
			return appendString(input.(string), suffix)
		}, nil
	default:
		return nil, errors.New("unable to create redaction function from config")
	}
}

// Function Definitions

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

func hashWithMD5(input string) (string, error) {
	hash := md5.Sum([]byte(input))
	return hex.EncodeToString(hash[:]), nil
}

func hashWithSHA1(input string) (string, error) {
	hash := sha1.Sum([]byte(input))
	return hex.EncodeToString(hash[:]), nil
}

func prepend(input string, prefix string) (string, error) {
	return prefix + input, nil
}

func camelPrepend(input string, prefix string) (string, error) {
	return prefix + strings.ToUpper(input[0:1]) + input[1:], nil
}

func appendString(input string, suffix string) (string, error) {
	return input + suffix, nil
}
