package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLifecycleEvidenceInvariants(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "docs", "architecture"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "docs", "architecture", "overview.md"), []byte("# Overview\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	manifestPath := filepath.Join(root, "requirements.yaml")
	manifest := `schema_version: 1
initiative_id: example
title: Example
status: verified
owner: "@owner"
requirements:
  - id: ACT-001
    group: activation
    priority: must
    state: verified
    title: Activate an item
    statement: Activation works.
    design_ref: architecture/overview.md
    acceptance:
      - id: ACT-001-A
        type: automated
        statement: The test passes.
      - id: ACT-001-B
        type: hardware
        statement: Hardware smoke passes.
    evidence:
      - acceptance_id: ACT-001-A
        kind: commit
        ref: git:0123456789abcdef
        observed_at: 2026-07-11
      - acceptance_id: ACT-001-B
        kind: hardware
        ref: receipt:hardware-smoke.json
        observed_at: 2026-07-11
        machine: MacBookPro18,3
        os_version: macOS-15.5
        display_topology: built-in-notch
    risks: []
`
	if err := os.WriteFile(manifestPath, []byte(manifest), 0o644); err != nil {
		t.Fatal(err)
	}

	m, parseProblems := parseManifest(manifestPath)
	if len(parseProblems) != 0 {
		t.Fatalf("parse problems: %v", parseProblems)
	}
	if problems := validateManifest(m, root); len(problems) != 0 {
		t.Fatalf("valid manifest rejected: %v", problems)
	}

	m.requirements[0].evidence[1].displayTopology = ""
	problems := validateManifest(m, root)
	if !containsProblem(problems, "requires machine, os_version, display_topology, and observed_at") {
		t.Fatalf("missing hardware metadata was not rejected: %v", problems)
	}
}

func TestImplementedAndShippedProof(t *testing.T) {
	req := &requirement{
		id: "REL-001", group: "release", priority: "must", state: "implemented",
		title: "Release", statement: "Release safely.", designRef: "overview.md",
		acceptance: []acceptanceCriterion{{id: "REL-001-A", kind: "automated"}},
	}
	m := manifest{schemaVersion: "1", initiativeID: "example", title: "Example", status: "implemented", owner: "@owner", requirements: []*requirement{req}}
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "docs"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "docs", "overview.md"), []byte("# Overview\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	problems := validateManifest(m, root)
	if !containsProblem(problems, "requires commit evidence") {
		t.Fatalf("implemented without commit was not rejected: %v", problems)
	}

	req.state = "shipped"
	req.evidence = []evidenceRecord{{acceptanceID: "REL-001-A", kind: "commit", ref: "git:abc", observedAt: "2026-07-11"}}
	problems = validateManifest(m, root)
	if !containsProblem(problems, "requires release evidence") {
		t.Fatalf("shipped without release was not rejected: %v", problems)
	}
}

func TestReceiptIdentityProblemsRejectsPersonalSigningIdentity(t *testing.T) {
	dirty := []byte(`{"signing_authority":"Apple Development: developer@example.invalid (ABCDEFGHIJ)"}`)
	problems := receiptIdentityProblems("receipt.json", dirty)
	if !containsProblem(problems, "developer@example.invalid") || !containsProblem(problems, "Apple Development:") || !containsProblem(problems, "ABCDEFGHIJ") {
		t.Fatalf("dirty receipt was not fully rejected: %v", problems)
	}

	clean := []byte(`{"signing_authority":"Apple Development (identity redacted)"}`)
	if problems := receiptIdentityProblems("receipt.json", clean); len(problems) != 0 {
		t.Fatalf("redacted receipt was rejected: %v", problems)
	}
}

func TestLocalCloseoutReceiptOnDiskHasNoIdentity(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	problems := validateLocalCloseoutReceipt(root)
	if len(problems) != 0 {
		t.Fatalf("checked-in closeout receipt still has identity: %v", problems)
	}
}

func TestValidateLocalCloseoutReceiptRequiresFile(t *testing.T) {
	problems := validateLocalCloseoutReceipt(t.TempDir())
	if !containsProblem(problems, "local closeout receipt missing") {
		t.Fatalf("missing receipt was not rejected: %v", problems)
	}
}

func containsProblem(problems []string, want string) bool {
	for _, problem := range problems {
		if strings.Contains(problem, want) {
			return true
		}
	}
	return false
}
