package main

import (
	"bytes"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

func main() {
	maxWarnings := flag.Int("max-warnings", 0, "maximum accepted swift-format warning count")
	flag.Parse()

	paths := flag.Args()
	if len(paths) == 0 {
		paths = []string{"Sources", "Tests"}
	}

	args := append([]string{"format", "lint", "-r"}, paths...)
	command := exec.Command("swift", args...)
	var output bytes.Buffer
	command.Stdout = &output
	command.Stderr = &output

	if err := command.Run(); err != nil {
		fmt.Fprint(os.Stderr, output.String())
		fmt.Fprintf(os.Stderr, "format-check: swift-format failed: %v\n", err)
		os.Exit(1)
	}

	warningCount := strings.Count(output.String(), "warning:")
	fmt.Printf(
		"format-check: %s warnings=%s baseline=%s\n",
		strings.Join(paths, ","),
		strconv.Itoa(warningCount),
		strconv.Itoa(*maxWarnings),
	)
	if warningCount > *maxWarnings {
		fmt.Fprint(os.Stderr, output.String())
		fmt.Fprintf(
			os.Stderr,
			"format-check: FAILED: warning count increased by %d\n",
			warningCount-*maxWarnings,
		)
		os.Exit(1)
	}

	if warningCount > 0 {
		fmt.Printf(
			"format-check: PASS (ratchet only; %d pre-existing findings remain debt)\n",
			warningCount,
		)
		return
	}
	fmt.Println("format-check: PASS (clean)")
}
