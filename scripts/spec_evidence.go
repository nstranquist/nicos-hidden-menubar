// Command spec_evidence validates the repository's lightweight specification
// and evidence contract without adding a package dependency to the app.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

var (
	requirementIDPattern = regexp.MustCompile(`^[A-Z][A-Z0-9]*-[0-9]{3}$`)
	markdownLinkPattern  = regexp.MustCompile(`\[[^]]*\]\(([^)]+)\)`)
)

type requirement struct {
	id         string
	group      string
	priority   string
	state      string
	title      string
	statement  string
	designRef  string
	acceptance []acceptanceCriterion
	evidence   []evidenceRecord
}

type acceptanceCriterion struct {
	id   string
	kind string
}

type evidenceRecord struct {
	acceptanceID    string
	kind            string
	ref             string
	observedAt      string
	machine         string
	osVersion       string
	displayTopology string
}

type manifest struct {
	schemaVersion string
	initiativeID  string
	title         string
	status        string
	owner         string
	requirements  []*requirement
}

func main() {
	repoRoot := flag.String("repo-root", ".", "repository root containing docs")
	requirementsPath := flag.String("requirements", "", "requirements manifest to validate")
	flag.Parse()

	if *requirementsPath == "" {
		fatalf("-requirements is required")
	}

	root, err := filepath.Abs(*repoRoot)
	if err != nil {
		fatalf("resolve repository root: %v", err)
	}
	manifestPath := *requirementsPath
	if !filepath.IsAbs(manifestPath) {
		manifestPath = filepath.Join(root, manifestPath)
	}

	m, problems := parseManifest(manifestPath)
	problems = append(problems, validateManifest(m, root)...)
	problems = append(problems, validateMarkdownLinks(filepath.Join(root, "docs"), root)...)
	problems = append(problems, validateLocalCloseoutReceipt(root)...)
	if len(problems) > 0 {
		sort.Strings(problems)
		for _, problem := range problems {
			fmt.Fprintf(os.Stderr, "docs-check: %s\n", problem)
		}
		os.Exit(1)
	}

	acceptanceCount := 0
	for _, req := range m.requirements {
		acceptanceCount += len(req.acceptance)
	}
	fmt.Printf("docs-check: ok (%d requirements, %d acceptance criteria)\n", len(m.requirements), acceptanceCount)
}

func parseManifest(path string) (manifest, []string) {
	file, err := os.Open(path)
	if err != nil {
		return manifest{}, []string{fmt.Sprintf("open requirements manifest: %v", err)}
	}
	defer file.Close()

	var m manifest
	var current *requirement
	var currentAcceptance *acceptanceCriterion
	var currentEvidence *evidenceRecord
	section := ""
	lineNumber := 0
	var problems []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		lineNumber++
		raw := scanner.Text()
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		indent := len(raw) - len(strings.TrimLeft(raw, " "))
		key, value, ok := splitYAMLField(strings.TrimPrefix(trimmed, "- "))
		if !ok {
			continue
		}

		switch {
		case indent == 0:
			section = ""
			currentAcceptance = nil
			currentEvidence = nil
			switch key {
			case "schema_version":
				m.schemaVersion = value
			case "initiative_id":
				m.initiativeID = value
			case "title":
				m.title = value
			case "status":
				m.status = value
			case "owner":
				m.owner = value
			case "requirements":
				section = "requirements"
			}
		case indent == 2 && strings.HasPrefix(trimmed, "- id:"):
			current = &requirement{id: value}
			m.requirements = append(m.requirements, current)
			section = "requirement"
			currentAcceptance = nil
			currentEvidence = nil
		case current != nil && indent == 4:
			switch key {
			case "group":
				current.group = value
			case "priority":
				current.priority = value
			case "state":
				current.state = value
			case "title":
				current.title = value
			case "statement":
				current.statement = value
			case "design_ref":
				current.designRef = value
			case "acceptance":
				section = "acceptance"
				currentAcceptance = nil
			case "evidence":
				section = "evidence"
				currentEvidence = nil
			}
		case current != nil && indent == 6 && section == "acceptance" && key == "id":
			current.acceptance = append(current.acceptance, acceptanceCriterion{id: value})
			currentAcceptance = &current.acceptance[len(current.acceptance)-1]
		case currentAcceptance != nil && indent == 8 && section == "acceptance" && key == "type":
			currentAcceptance.kind = value
		case current != nil && indent == 6 && section == "evidence" && key == "acceptance_id":
			current.evidence = append(current.evidence, evidenceRecord{acceptanceID: value})
			currentEvidence = &current.evidence[len(current.evidence)-1]
		case currentEvidence != nil && indent == 8 && section == "evidence":
			switch key {
			case "kind":
				currentEvidence.kind = value
			case "ref":
				currentEvidence.ref = value
			case "observed_at":
				currentEvidence.observedAt = value
			case "machine":
				currentEvidence.machine = value
			case "os_version":
				currentEvidence.osVersion = value
			case "display_topology":
				currentEvidence.displayTopology = value
			}
		}
	}
	if err := scanner.Err(); err != nil {
		problems = append(problems, fmt.Sprintf("read requirements manifest near line %d: %v", lineNumber, err))
	}
	return m, problems
}

func validateManifest(m manifest, root string) []string {
	var problems []string
	if m.schemaVersion != "1" {
		problems = append(problems, "schema_version must be 1")
	}
	if m.initiativeID == "" {
		problems = append(problems, "initiative_id is required")
	}
	if m.title == "" {
		problems = append(problems, "title is required")
	}
	if m.owner == "" {
		problems = append(problems, "owner is required")
	}
	if !oneOf(m.status, validStates()...) {
		problems = append(problems, fmt.Sprintf("initiative status %q is invalid", m.status))
	}
	if len(m.requirements) == 0 {
		problems = append(problems, "at least one requirement is required")
	}

	seenRequirements := make(map[string]bool)
	seenAcceptance := make(map[string]bool)
	for _, req := range m.requirements {
		label := req.id
		if label == "" {
			label = "<missing id>"
		}
		if !requirementIDPattern.MatchString(req.id) {
			problems = append(problems, fmt.Sprintf("requirement %s has an invalid id", label))
		}
		if seenRequirements[req.id] {
			problems = append(problems, fmt.Sprintf("requirement id %s is duplicated", label))
		}
		seenRequirements[req.id] = true
		if req.group == "" || req.title == "" || req.statement == "" || req.designRef == "" {
			problems = append(problems, fmt.Sprintf("requirement %s is missing group, title, statement, or design_ref", label))
		}
		if !oneOf(req.priority, "must", "should", "could") {
			problems = append(problems, fmt.Sprintf("requirement %s priority %q is invalid", label, req.priority))
		}
		if !oneOf(req.state, validStates()...) {
			problems = append(problems, fmt.Sprintf("requirement %s state %q is invalid", label, req.state))
		}
		if req.designRef != "" {
			designPath := strings.Split(req.designRef, "#")[0]
			if _, err := os.Stat(filepath.Join(root, "docs", filepath.FromSlash(designPath))); err != nil {
				problems = append(problems, fmt.Sprintf("requirement %s design_ref %q does not resolve from docs/", label, req.designRef))
			}
		}
		if len(req.acceptance) == 0 {
			problems = append(problems, fmt.Sprintf("requirement %s needs acceptance criteria", label))
		}

		evidenceByAcceptance := make(map[string][]evidenceRecord)
		hasCommit := false
		hasRelease := false
		for _, evidence := range req.evidence {
			evidenceByAcceptance[evidence.acceptanceID] = append(evidenceByAcceptance[evidence.acceptanceID], evidence)
			if evidence.acceptanceID == "" || evidence.kind == "" || evidence.ref == "" || evidence.observedAt == "" {
				problems = append(problems, fmt.Sprintf("requirement %s has evidence missing acceptance_id, kind, ref, or observed_at", label))
			}
			if evidence.kind == "commit" && evidence.ref != "" {
				hasCommit = true
			}
			if evidence.kind == "release" && evidence.ref != "" {
				hasRelease = true
			}
		}
		if oneOf(req.state, "implemented", "verified", "shipped") && !hasCommit {
			problems = append(problems, fmt.Sprintf("requirement %s state %s requires commit evidence", label, req.state))
		}
		if req.state == "shipped" && !hasRelease {
			problems = append(problems, fmt.Sprintf("requirement %s state shipped requires release evidence", label))
		}

		acceptanceForRequirement := make(map[string]bool)
		for _, criterion := range req.acceptance {
			acceptanceID := criterion.id
			acceptanceForRequirement[acceptanceID] = true
			if !strings.HasPrefix(acceptanceID, req.id+"-") {
				problems = append(problems, fmt.Sprintf("acceptance id %s must begin with %s-", acceptanceID, req.id))
			}
			if seenAcceptance[acceptanceID] {
				problems = append(problems, fmt.Sprintf("acceptance id %s is duplicated", acceptanceID))
			}
			seenAcceptance[acceptanceID] = true
			records := evidenceByAcceptance[acceptanceID]
			if oneOf(req.state, "verified", "shipped") && len(records) == 0 {
				problems = append(problems, fmt.Sprintf("requirement %s lacks evidence for %s", label, acceptanceID))
			}
			if oneOf(req.state, "verified", "shipped") && criterion.kind == "hardware" && !hasHardwareMetadata(records) {
				problems = append(problems, fmt.Sprintf("requirement %s hardware evidence for %s requires machine, os_version, display_topology, and observed_at", label, acceptanceID))
			}
		}
		for acceptanceID := range evidenceByAcceptance {
			if !acceptanceForRequirement[acceptanceID] {
				problems = append(problems, fmt.Sprintf("requirement %s has evidence for unknown acceptance id %s", label, acceptanceID))
			}
		}
	}
	return problems
}

func hasHardwareMetadata(records []evidenceRecord) bool {
	for _, record := range records {
		if record.kind == "hardware" && record.ref != "" && record.observedAt != "" && record.machine != "" && record.osVersion != "" && record.displayTopology != "" {
			return true
		}
	}
	return false
}

var localCloseoutReceiptRel = filepath.Join(
	"docs", "initiatives", "v0.2-production-hardening", "receipts", "LOCAL-20260731.json",
)

var (
	forbiddenReceiptIdentity = []string{
		"Apple Development:",
	}
	signingAuthorityEmailPattern = regexp.MustCompile(
		`(?i)"signing_authority"\s*:\s*"[^"]*@[^"]*"`,
	)
	signingAuthorityTeamPattern = regexp.MustCompile(
		`(?i)"signing_authority"\s*:\s*"[^"]*\([A-Z0-9]{10}\)[^"]*"`,
	)
)

func validateLocalCloseoutReceipt(root string) []string {
	path := filepath.Join(root, localCloseoutReceiptRel)
	body, err := os.ReadFile(path)
	if err != nil {
		return []string{fmt.Sprintf("local closeout receipt missing: %s", filepath.ToSlash(localCloseoutReceiptRel))}
	}
	return receiptIdentityProblems(filepath.ToSlash(localCloseoutReceiptRel), body)
}

func receiptIdentityProblems(label string, body []byte) []string {
	text := string(body)
	var problems []string
	for _, token := range forbiddenReceiptIdentity {
		if strings.Contains(text, token) {
			problems = append(problems, fmt.Sprintf("%s contains redacted identity token %q", label, token))
		}
	}
	if signingAuthorityEmailPattern.Match(body) {
		problems = append(problems, fmt.Sprintf("%s contains an unredacted signing-authority email", label))
	}
	if signingAuthorityTeamPattern.Match(body) {
		problems = append(problems, fmt.Sprintf("%s contains an unredacted signing-authority team identifier", label))
	}
	return problems
}

func validateMarkdownLinks(docsRoot, repoRoot string) []string {
	var problems []string
	err := filepath.WalkDir(docsRoot, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() || !strings.HasSuffix(strings.ToLower(path), ".md") {
			return nil
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		for _, match := range markdownLinkPattern.FindAllStringSubmatch(string(contents), -1) {
			target := strings.TrimSpace(strings.Trim(match[1], "<>"))
			if target == "" || strings.HasPrefix(target, "#") || strings.Contains(target, "://") || strings.HasPrefix(target, "mailto:") {
				continue
			}
			target = strings.Split(strings.Split(target, "#")[0], "?")[0]
			decoded, err := url.PathUnescape(target)
			if err != nil {
				decoded = target
			}
			resolved := filepath.Join(filepath.Dir(path), filepath.FromSlash(decoded))
			if strings.HasPrefix(decoded, "/") {
				resolved = filepath.Join(repoRoot, filepath.FromSlash(strings.TrimPrefix(decoded, "/")))
			}
			if _, err := os.Stat(resolved); err != nil {
				rel, _ := filepath.Rel(repoRoot, path)
				problems = append(problems, fmt.Sprintf("%s has a broken local link %q", filepath.ToSlash(rel), match[1]))
			}
		}
		return nil
	})
	if err != nil {
		problems = append(problems, fmt.Sprintf("walk docs: %v", err))
	}
	return problems
}

func splitYAMLField(line string) (string, string, bool) {
	key, value, ok := strings.Cut(line, ":")
	if !ok {
		return "", "", false
	}
	return strings.TrimSpace(key), strings.Trim(strings.TrimSpace(value), `"'`), true
}

func validStates() []string {
	return []string{"proposed", "accepted", "implemented", "verified", "shipped", "deferred"}
}

func oneOf(value string, choices ...string) bool {
	for _, choice := range choices {
		if value == choice {
			return true
		}
	}
	return false
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "docs-check: "+format+"\n", args...)
	os.Exit(2)
}
