package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type receipt struct {
	SchemaVersion       int       `json:"schema_version"`
	GeneratedAt         time.Time `json:"generated_at"`
	AppName             string    `json:"app_name"`
	Version             string    `json:"version"`
	Build               string    `json:"build"`
	Commit              string    `json:"commit"`
	WorkingTreeDirty    bool      `json:"working_tree_dirty"`
	Archive             string    `json:"archive"`
	SHA256              string    `json:"sha256"`
	CodeSignAuthority   string    `json:"codesign_authority"`
	DeveloperIDSigned   bool      `json:"developer_id_signed"`
	NotarizationStapled bool      `json:"notarization_stapled"`
	DistributionReady   bool      `json:"distribution_ready"`
	Blockers            []string  `json:"blockers,omitempty"`
}

func commandOutput(name string, args ...string) (string, error) {
	command := exec.Command(name, args...)
	output, err := command.CombinedOutput()
	return strings.TrimSpace(string(output)), err
}

func plistValue(appPath, key string) (string, error) {
	return commandOutput(
		"plutil",
		"-extract", key,
		"raw",
		"-o", "-",
		filepath.Join(appPath, "Contents", "Info.plist"),
	)
}

func signatureAuthority(appPath string) (string, error) {
	output, err := commandOutput("codesign", "-dv", "--verbose=4", appPath)
	if err != nil {
		return "", fmt.Errorf("inspect signature: %w: %s", err, output)
	}
	for _, line := range strings.Split(output, "\n") {
		if strings.HasPrefix(line, "Authority=") {
			return strings.TrimPrefix(line, "Authority="), nil
		}
	}
	return "", fmt.Errorf("signature has no Authority field")
}

func fileSHA256(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()

	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func fatal(format string, values ...any) {
	fmt.Fprintf(os.Stderr, "release-artifact: "+format+"\n", values...)
	os.Exit(1)
}

func main() {
	appPath := flag.String("app", "", "path to signed .app bundle")
	outputDirectory := flag.String("out", ".local/release", "artifact output directory")
	flag.Parse()

	if *appPath == "" {
		fatal("-app is required")
	}
	if _, err := os.Stat(*appPath); err != nil {
		fatal("app bundle unavailable: %v", err)
	}
	if output, err := commandOutput("codesign", "--verify", "--deep", "--strict", *appPath); err != nil {
		fatal("signature verification failed: %v: %s", err, output)
	}

	version, err := plistValue(*appPath, "CFBundleShortVersionString")
	if err != nil {
		fatal("read version: %v", err)
	}
	build, err := plistValue(*appPath, "CFBundleVersion")
	if err != nil {
		fatal("read build: %v", err)
	}
	authority, err := signatureAuthority(*appPath)
	if err != nil {
		fatal("%v", err)
	}
	commit, err := commandOutput("git", "rev-parse", "HEAD")
	if err != nil {
		fatal("read commit: %v", err)
	}
	status, err := commandOutput("git", "status", "--porcelain")
	if err != nil {
		fatal("read working-tree state: %v", err)
	}

	if err := os.MkdirAll(*outputDirectory, 0o755); err != nil {
		fatal("create output directory: %v", err)
	}
	baseName := fmt.Sprintf("NicosHiddenMenuBar-%s", version)
	archivePath := filepath.Join(*outputDirectory, baseName+".zip")
	if err := os.Remove(archivePath); err != nil && !os.IsNotExist(err) {
		fatal("replace prior archive: %v", err)
	}
	if output, err := commandOutput("ditto", "-c", "-k", "--keepParent", *appPath, archivePath); err != nil {
		fatal("create archive: %v: %s", err, output)
	}
	checksum, err := fileSHA256(archivePath)
	if err != nil {
		fatal("checksum archive: %v", err)
	}

	_, stapleErr := commandOutput("xcrun", "stapler", "validate", *appPath)
	developerID := strings.HasPrefix(authority, "Developer ID Application:")
	stapled := stapleErr == nil
	blockers := []string{}
	if status != "" {
		blockers = append(blockers, "working tree is dirty")
	}
	if !developerID {
		blockers = append(blockers, "artifact is not signed with Developer ID Application")
	}
	if !stapled {
		blockers = append(blockers, "artifact has no valid stapled notarization ticket")
	}

	result := receipt{
		SchemaVersion:       1,
		GeneratedAt:         time.Now().UTC(),
		AppName:             filepath.Base(*appPath),
		Version:             version,
		Build:               build,
		Commit:              commit,
		WorkingTreeDirty:    status != "",
		Archive:             filepath.Base(archivePath),
		SHA256:              checksum,
		CodeSignAuthority:   authority,
		DeveloperIDSigned:   developerID,
		NotarizationStapled: stapled,
		DistributionReady:   status == "" && developerID && stapled,
		Blockers:            blockers,
	}

	receiptPath := filepath.Join(*outputDirectory, baseName+".provenance.json")
	encoded, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		fatal("encode receipt: %v", err)
	}
	encoded = append(encoded, '\n')
	if err := os.WriteFile(receiptPath, encoded, 0o644); err != nil {
		fatal("write receipt: %v", err)
	}

	fmt.Printf("release-artifact: archive=%s\n", archivePath)
	fmt.Printf("release-artifact: sha256=%s\n", checksum)
	fmt.Printf("release-artifact: receipt=%s\n", receiptPath)
	fmt.Printf("release-artifact: distribution_ready=%t\n", result.DistributionReady)
	if len(blockers) > 0 {
		fmt.Printf("release-artifact: blockers=%s\n", strings.Join(blockers, "; "))
	}
}
