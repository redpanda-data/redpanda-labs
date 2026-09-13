package functions

import (
	"bytes"
	"crypto/md5"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"github.com/pmw-rp/jsonparser"
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

func BuildFunction(config map[string]any) (func([]byte) ([]byte, error), error) {
	fn := config["function"]
	switch fn {
	case "replace":
		err := validateConfig(config, map[string]reflect.Kind{"replacement": reflect.String})
		if err != nil {
			return nil, err
		}
		replacement := []byte(config["replacement"].(string))
		return func(input []byte) ([]byte, error) {
			return replace(input, replacement)
		}, nil
	case "replaceBeforeSeparator":
		err := validateConfig(config, map[string]reflect.Kind{"replacement": reflect.String, "separator": reflect.String})
		if err != nil {
			return nil, err
		}
		replacement := []byte(config["replacement"].(string))
		separator := []byte(config["separator"].(string))
		return func(input []byte) ([]byte, error) {
			return replaceBeforeSeparator(input, replacement, separator)
		}, nil
	case "truncateFloat64":
		err := validateConfig(config, map[string]reflect.Kind{"decimals": reflect.Int})
		if err != nil {
			return nil, err
		}
		decimals := config["decimals"].(int)
		return func(input []byte) ([]byte, error) {
			return truncateFloat64(input, decimals)
		}, nil
	case "md5":
		return func(input []byte) ([]byte, error) {
			return hashWithMD5(input)
		}, nil
	case "sha1":
		return func(input []byte) ([]byte, error) {
			return hashWithSHA1(input)
		}, nil
	case "prepend":
		err := validateConfig(config, map[string]reflect.Kind{"prefix": reflect.String})
		if err != nil {
			return nil, err
		}
		prefix := []byte(config["prefix"].(string))
		return func(input []byte) ([]byte, error) {
			return prepend(input, prefix)
		}, nil
	case "camelPrepend":
		err := validateConfig(config, map[string]reflect.Kind{"prefix": reflect.String})
		if err != nil {
			return nil, err
		}
		prefix := []byte(config["prefix"].(string))
		return func(input []byte) ([]byte, error) {
			return camelPrepend(input, prefix)
		}, nil
	case "append":
		err := validateConfig(config, map[string]reflect.Kind{"suffix": reflect.String})
		if err != nil {
			return nil, err
		}
		suffix := []byte(config["suffix"].(string))
		return func(input []byte) ([]byte, error) {
			return appendString(input, suffix)
		}, nil
	case "x-digits":
		err := validateConfig(config, map[string]reflect.Kind{"i": reflect.Int})
		if err != nil {
			return nil, err
		}
		i := config["i"].(int)
		return func(input []byte) ([]byte, error) {
			return xDigits(input, i)
		}, nil
	default:
		return nil, errors.New("unable to create redaction function from config")
	}
}

// Function Definitions

func replace(input []byte, replacement []byte) ([]byte, error) {
	return replacement, nil
}

func replaceBeforeSeparator(input []byte, replacement []byte, separator []byte) ([]byte, error) {
	if !bytes.Contains(input, separator) {
		return []byte{}, errors.New(fmt.Sprintf("input string \"%s\" doesn't contain separator \"%s\"", input, separator))
	}
	split := bytes.Split(input, separator)
	if len(split) != 2 {
		return []byte{}, errors.New(fmt.Sprintf("input string \"%s\" contains multiple separators \"%s\"", input, separator))
	}
	var result []byte
	result = append(result, replacement...)
	result = append(result, separator...)
	result = append(result, split[1]...)
	return result, nil
}

func truncateFloat64(input []byte, decimals int) ([]byte, error) {
	format := "%." + strconv.Itoa(decimals) + "f"
	parsedFloat, err := jsonparser.ParseFloat(input)
	if err != nil {
		return []byte{}, errors.New("unable to parse float")
	}
	s := fmt.Sprintf(format, parsedFloat)
	return []byte(s), nil
}

func hashWithMD5(input []byte) ([]byte, error) {
	hash := md5.Sum(input)
	return []byte(hex.EncodeToString(hash[:])), nil
}

func hashWithSHA1(input []byte) ([]byte, error) {
	hash := sha1.Sum(input)
	return []byte(hex.EncodeToString(hash[:])), nil
}

func prepend(input []byte, prefix []byte) ([]byte, error) {
	var result []byte
	result = append(result, prefix...)
	result = append(result, input...)
	return result, nil
}

func camelPrepend(input []byte, prefix []byte) ([]byte, error) {
	var result []byte
	result = append(result, prefix...)
	result = append(result, []byte(strings.ToUpper(string(input[0:1])))...)
	result = append(result, input[1:]...)
	return result, nil
}

func appendString(input []byte, suffix []byte) ([]byte, error) {
	var result []byte
	result = append(result, input...)
	result = append(result, suffix...)
	return result, nil
}

func xDigits(input []byte, i int) ([]byte, error) {
	var result []byte

	pre := input[0 : len(input)-i]
	post := input[len(input)-i : len(input)]

	for _, b := range pre {
		if b >= '0' && b <= '9' {
			result = append(result, 'X')
		} else {
			result = append(result, b)
		}
	}

	result = append(result, post...)

	return result, nil
}
