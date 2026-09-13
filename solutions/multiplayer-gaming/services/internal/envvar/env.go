// Package envvar reads the small set of environment variables every service in
// this solution is configured with. Defaults match docker-compose.yml.
package envvar

import (
	"os"
	"strconv"
	"strings"
)

// String returns the variable or def when it is unset or empty.
func String(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

// Int returns the variable parsed as an integer or def when unset or invalid.
func Int(key string, def int) int {
	v := String(key, "")
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

// Int64 returns the variable parsed as an int64 or def when unset or invalid.
func Int64(key string, def int64) int64 {
	v := String(key, "")
	if v == "" {
		return def
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		return def
	}
	return n
}

// Bool is true for 1, true, yes, on (case-insensitive).
func Bool(key string, def bool) bool {
	v := strings.ToLower(String(key, ""))
	if v == "" {
		return def
	}
	switch v {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	}
	return def
}

// List splits a comma separated variable.
func List(key, def string) []string {
	var out []string
	for _, p := range strings.Split(String(key, def), ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
