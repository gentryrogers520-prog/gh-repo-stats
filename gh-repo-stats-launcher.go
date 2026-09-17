package main

import (
	"embed"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"syscall"
)

//go:embed gh-repo-stats
var scriptFS embed.FS

func main() {
	script, err := scriptFS.ReadFile("gh-repo-stats")
	if err != nil {
		fail(err)
	}

	bashPath, err := findBash()
	if err != nil {
		fail(err)
	}

	tempDir, err := os.MkdirTemp("", "gh-repo-stats-*")
	if err != nil {
		fail(err)
	}
	defer os.RemoveAll(tempDir)

	scriptPath := filepath.Join(tempDir, "gh-repo-stats")
	if err := os.WriteFile(scriptPath, script, 0o700); err != nil {
		fail(err)
	}

	cmd := exec.Command(bashPath, append([]string{scriptPath}, os.Args[1:]...)...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()

	if err := cmd.Run(); err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			if status, ok := exitErr.Sys().(syscall.WaitStatus); ok {
				os.Exit(status.ExitStatus())
			}
			os.Exit(exitErr.ExitCode())
		}
		fail(err)
	}
}

func findBash() (string, error) {
	if bashPath, err := exec.LookPath("bash"); err == nil {
		return bashPath, nil
	}

	if runtime.GOOS == "windows" {
		candidates := []string{
			`C:\Program Files\Git\bin\bash.exe`,
			`C:\Program Files\Git\usr\bin\bash.exe`,
			`C:\Program Files (x86)\Git\bin\bash.exe`,
			`C:\Program Files (x86)\Git\usr\bin\bash.exe`,
		}

		for _, candidate := range candidates {
			if _, err := os.Stat(candidate); err == nil {
				return candidate, nil
			}
		}
	}

	return "", errors.New("bash is required to run gh-repo-stats")
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
