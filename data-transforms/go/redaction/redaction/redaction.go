package redaction

import (
	"errors"
	"redactor/redactors"
)

func Wrap(message string, err error) error {
	return errors.Join(errors.New(message), err)
}

func Redact(input []byte) ([]byte, error) {
	data, err := redactors.Process(input)
	if err != nil {
		return []byte{}, Wrap("unable to redact record", err)
	}
	return data, nil
}

func Initialise(bytes []byte) error {
	err := redactors.Configure([]byte(redactors.Builtins))
	if err != nil {
		return Wrap("unable to configure built-in redactors", err)
	}
	err = redactors.Configure(bytes)
	if err != nil {
		return Wrap("unable to configure custom redactors", err)
	}
	return nil
}
