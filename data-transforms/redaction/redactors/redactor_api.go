package redactors

type RedactorApi interface {
	getKey() string
	getValue() any
	add(key string, value any)
	drop()
	setValue(value any)
}
