package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"redactor/redaction"
)

func readToBytes(filename string) ([]byte, error) {
	file, err := os.Open(filename)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	// Get the file size
	stat, err := file.Stat()
	if err != nil {
		fmt.Println(err)
		return nil, err
	}

	// Read the file into a byte slice
	bs := make([]byte, stat.Size())
	_, err = bufio.NewReader(file).Read(bs)
	if err != nil && err != io.EOF {
		fmt.Println(err)
		return nil, err
	}

	return bs, nil
}

func processArguments() ([]byte, []byte) {
	configFilename := flag.String("config", "example/config.yaml", "filename of the redaction config")
	inputFilename := flag.String("input", "example/input.json", "filename of the JSON message to parse")

	flag.Parse()

	if _, err := os.Stat(*configFilename); errors.Is(err, os.ErrNotExist) {
		fmt.Printf("config file does not exist: %s", *configFilename)
		os.Exit(1)
	}

	if _, err := os.Stat(*inputFilename); errors.Is(err, os.ErrNotExist) {
		fmt.Printf("input file does not exist: %s", *inputFilename)
		os.Exit(1)
	}
	config, err := readToBytes(*configFilename)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	input, err := readToBytes(*inputFilename)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	return config, input
}

func main() {
	config, input := processArguments()
	redaction.Initialise(config)
	redacted, err := redaction.Redact(input)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	output := string(redacted)
	fmt.Println(output)
}
