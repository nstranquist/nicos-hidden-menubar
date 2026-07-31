// Command perf_gate records local PERF-001 evidence for the installed app.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	processName = "NicosHiddenMenuBar"
	appPath     = "/Applications/NicosHiddenMenuBar.app"
	urlReveal   = "nicoshiddenbar://reveal-panel"
	urlDismiss  = "nicoshiddenbar://dismiss-panel"
)

type revealSample struct {
	ShellMilliseconds      float64 `json:"shellMilliseconds"`
	ContentMilliseconds    float64 `json:"contentMilliseconds"`
	ShellItemCount         *int    `json:"shellItemCount"`
	ItemCount              int     `json:"itemCount"`
	ImageCount             int     `json:"imageCount"`
	AccessibilityTrusted   *bool   `json:"accessibilityTrusted"`
	ScreenRecordingGranted *bool   `json:"screenRecordingGranted"`
	Warm                   bool    `json:"warm"`
	ObservedAt             string  `json:"observedAt"`
}

type diagnosticsFile struct {
	Performance *struct {
		RevealSamples []revealSample `json:"revealSamples"`
	} `json:"performance"`
}

type processSample struct {
	ObservedAt     string  `json:"observed_at"`
	CPUPercent     float64 `json:"cpu_percent"`
	CPUTimeSeconds float64 `json:"cpu_time_seconds"`
	RSSBytes       int64   `json:"rss_bytes"`
}

type metricResult struct {
	Observed float64 `json:"observed"`
	Budget   float64 `json:"budget"`
	Unit     string  `json:"unit"`
	OK       bool    `json:"ok"`
}

type receipt struct {
	SchemaVersion int    `json:"schema_version"`
	RequirementID string `json:"requirement_id"`
	ObservedAt    string `json:"observed_at"`
	Environment   struct {
		Machine                string `json:"machine"`
		OSVersion              string `json:"os_version"`
		DisplayTopology        string `json:"display_topology"`
		AppPath                string `json:"app_path"`
		AppVersion             string `json:"app_version"`
		Commit                 string `json:"commit"`
		WorkingTreeDirty       bool   `json:"working_tree_dirty"`
		AccessibilityTrusted   *bool  `json:"accessibility_trusted"`
		ScreenRecordingGranted *bool  `json:"screen_recording_granted"`
	} `json:"environment"`
	Measurement struct {
		DurationSeconds float64         `json:"duration_seconds"`
		IntervalSeconds float64         `json:"interval_seconds"`
		SettleSeconds   float64         `json:"settle_seconds"`
		ProcessSamples  []processSample `json:"process_samples"`
		RevealSamples   []revealSample  `json:"reveal_samples"`
	} `json:"measurement"`
	Results struct {
		IdleCPUAverage         metricResult `json:"idle_cpu_average"`
		IdleRSSMaximum         metricResult `json:"idle_rss_maximum"`
		ColdShell              metricResult `json:"cold_shell"`
		ColdContent            metricResult `json:"cold_content"`
		WarmRevealP95          metricResult `json:"warm_reveal_p95"`
		RevealSampleSufficient bool         `json:"reveal_sample_sufficient"`
		WarmShellHasContent    bool         `json:"warm_shell_has_content"`
	} `json:"results"`
	OK          bool     `json:"ok"`
	Limitations []string `json:"limitations"`
}

func main() {
	duration := flag.Duration("duration", 5*time.Minute, "idle sampling duration")
	interval := flag.Duration("interval", 5*time.Second, "idle sampling interval")
	settle := flag.Duration("settle", 15*time.Second, "settling time after reveal cycles")
	revealCycles := flag.Int("reveal-cycles", 12, "cold plus warm reveal cycles")
	maxRSSMB := flag.Float64("max-rss-mb", 80, "maximum physical footprint in MiB")
	allowUIAutomation := flag.Bool(
		"allow-ui-automation",
		false,
		"explicitly allow repeated visible panel open/dismiss cycles",
	)
	out := flag.String("out", "", "receipt output path; stdout when empty")
	diagnosticsPath := flag.String(
		"diagnostics",
		filepath.Join(userHome(), ".config", "nicos-hidden-menubar", "diagnostics.json"),
		"diagnostics JSON path",
	)
	flag.Parse()

	if *duration <= 0 || *interval <= 0 || *settle < 0 || *revealCycles < 3 || *maxRSSMB <= 0 {
		fatal("duration/interval/max-rss must be positive, settle non-negative, and reveal-cycles at least 3")
	}
	if !*allowUIAutomation {
		fatal("refusing visible panel automation; rerun with -allow-ui-automation=true after notifying the active user")
	}
	if _, err := os.Stat(appPath); err != nil {
		fatal(fmt.Sprintf("installed app unavailable: %v", err))
	}

	startedAt := time.Now().UTC()
	if err := restartApp(); err != nil {
		fatal(err.Error())
	}
	pid, err := waitForPID(10 * time.Second)
	if err != nil {
		fatal(err.Error())
	}

	for index := 0; index < *revealCycles; index++ {
		if err := openURL(urlReveal); err != nil {
			fatal(fmt.Sprintf("reveal cycle %d: %v", index+1, err))
		}
		time.Sleep(450 * time.Millisecond)
		if err := openURL(urlDismiss); err != nil {
			fatal(fmt.Sprintf("dismiss cycle %d: %v", index+1, err))
		}
		time.Sleep(250 * time.Millisecond)
	}

	reveals, err := readRevealSamples(*diagnosticsPath, startedAt)
	if err != nil {
		fatal(err.Error())
	}
	time.Sleep(*settle)
	processSamples, err := sampleProcess(pid, *duration, *interval)
	if err != nil {
		fatal(err.Error())
	}

	value := buildReceipt(
		startedAt,
		*duration,
		*interval,
		*settle,
		*maxRSSMB,
		reveals,
		processSamples,
	)
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		fatal(err.Error())
	}
	data = append(data, '\n')
	if *out == "" {
		_, _ = os.Stdout.Write(data)
	} else {
		if err := os.MkdirAll(filepath.Dir(*out), 0o755); err != nil {
			fatal(err.Error())
		}
		if err := os.WriteFile(*out, data, 0o644); err != nil {
			fatal(err.Error())
		}
		fmt.Printf("performance receipt: %s\n", *out)
	}
	if !value.OK {
		os.Exit(1)
	}
	fmt.Println("performance gate passed")
}

func buildReceipt(
	startedAt time.Time,
	duration time.Duration,
	interval time.Duration,
	settle time.Duration,
	maxRSSMB float64,
	reveals []revealSample,
	processSamples []processSample,
) receipt {
	var value receipt
	value.SchemaVersion = 1
	value.RequirementID = "PERF-001"
	value.ObservedAt = time.Now().UTC().Format(time.RFC3339)
	value.Environment.Machine = commandOutput("sysctl", "-n", "hw.model")
	value.Environment.OSVersion = strings.ReplaceAll(commandOutput("sw_vers"), "\n", "; ")
	value.Environment.DisplayTopology = displayTopology()
	value.Environment.AppPath = appPath
	value.Environment.AppVersion = commandOutput(
		"plutil",
		"-extract", "CFBundleShortVersionString",
		"raw",
		"-o", "-",
		filepath.Join(appPath, "Contents", "Info.plist"),
	)
	value.Environment.Commit = commandOutput("git", "rev-parse", "HEAD")
	value.Environment.WorkingTreeDirty = commandOutput("git", "status", "--porcelain") != ""
	if len(reveals) > 0 {
		value.Environment.AccessibilityTrusted = reveals[0].AccessibilityTrusted
		value.Environment.ScreenRecordingGranted = reveals[0].ScreenRecordingGranted
	}
	value.Measurement.DurationSeconds = duration.Seconds()
	value.Measurement.IntervalSeconds = interval.Seconds()
	value.Measurement.SettleSeconds = settle.Seconds()
	value.Measurement.ProcessSamples = processSamples
	value.Measurement.RevealSamples = reveals

	rssValues := make([]float64, 0, len(processSamples))
	for _, sample := range processSamples {
		rssValues = append(rssValues, float64(sample.RSSBytes)/(1024*1024))
	}
	cold := firstCold(reveals)
	warmShell := make([]float64, 0, len(reveals))
	warmContent := make([]float64, 0, len(reveals))
	warmShellHasContent := true
	for _, sample := range reveals {
		if sample.Warm {
			warmShell = append(warmShell, sample.ShellMilliseconds)
			warmContent = append(warmContent, sample.ContentMilliseconds)
			if sample.ShellItemCount == nil || *sample.ShellItemCount == 0 {
				warmShellHasContent = false
			}
		}
	}

	value.Results.IdleCPUAverage = result(cpuTimeAverage(processSamples), 0.1, "percent")
	value.Results.IdleRSSMaximum = result(maximum(rssValues), maxRSSMB, "MiB")
	value.Results.ColdShell = result(cold.ShellMilliseconds, 250, "milliseconds")
	value.Results.ColdContent = result(cold.ContentMilliseconds, 750, "milliseconds")
	value.Results.WarmRevealP95 = result(percentile(warmShell, 0.95), 150, "milliseconds")
	value.Results.RevealSampleSufficient = cold.ObservedAt != "" && len(warmShell) >= 8
	value.Results.WarmShellHasContent = warmShellHasContent && len(warmContent) >= 8
	value.Limitations = []string{
		"Screen Recording icon completion is represented only when permission is granted.",
		"External-display reconciliation is outside this built-in-display performance receipt.",
	}
	value.OK = len(processSamples) >= 2 &&
		value.Results.RevealSampleSufficient &&
		value.Results.IdleCPUAverage.OK &&
		value.Results.IdleRSSMaximum.OK &&
		value.Results.ColdShell.OK &&
		value.Results.ColdContent.OK &&
		value.Results.WarmRevealP95.OK &&
		value.Results.WarmShellHasContent
	return value
}

func result(observed, budget float64, unit string) metricResult {
	valid := !math.IsNaN(observed) && !math.IsInf(observed, 0)
	if !valid {
		observed = -1
	}
	return metricResult{
		Observed: observed,
		Budget:   budget,
		Unit:     unit,
		OK:       valid && observed <= budget,
	}
}

func restartApp() error {
	_ = exec.Command("/usr/bin/pkill", "-x", processName).Run()
	time.Sleep(400 * time.Millisecond)
	if output, err := exec.Command("/usr/bin/open", appPath).CombinedOutput(); err != nil {
		return fmt.Errorf("open installed app: %w: %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func waitForPID(timeout time.Duration) (int, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		text := commandOutput("/usr/bin/pgrep", "-x", processName)
		if pid, err := strconv.Atoi(strings.TrimSpace(strings.Split(text, "\n")[0])); err == nil && pid > 0 {
			return pid, nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return 0, errors.New("app did not launch before timeout")
}

func openURL(value string) error {
	output, err := exec.Command("/usr/bin/open", value).CombinedOutput()
	if err != nil {
		return fmt.Errorf("open %s: %w: %s", value, err, strings.TrimSpace(string(output)))
	}
	return nil
}

func readRevealSamples(path string, startedAt time.Time) ([]revealSample, error) {
	var decoded diagnosticsFile
	deadline := time.Now().Add(3 * time.Second)
	for {
		data, err := os.ReadFile(path)
		if err == nil && json.Unmarshal(data, &decoded) == nil && decoded.Performance != nil {
			var selected []revealSample
			for _, sample := range decoded.Performance.RevealSamples {
				at, parseErr := time.Parse(time.RFC3339, sample.ObservedAt)
				if parseErr == nil && !at.Before(startedAt) {
					selected = append(selected, sample)
				}
			}
			if len(selected) >= 3 {
				return selected, nil
			}
		}
		if time.Now().After(deadline) {
			return nil, fmt.Errorf("fewer than three current reveal samples in %s", path)
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func sampleProcess(pid int, duration, interval time.Duration) ([]processSample, error) {
	deadline := time.Now().Add(duration)
	var samples []processSample
	for {
		output, err := exec.Command(
			"/bin/ps",
			"-p", strconv.Itoa(pid),
			"-o", "%cpu=",
			"-o", "rss=",
			"-o", "time=",
		).Output()
		if err != nil {
			return nil, fmt.Errorf("sample process %d: %w", pid, err)
		}
		fields := strings.Fields(string(output))
		if len(fields) != 3 {
			return nil, fmt.Errorf("unexpected ps output %q", strings.TrimSpace(string(output)))
		}
		cpu, cpuErr := strconv.ParseFloat(fields[0], 64)
		rssKB, rssErr := strconv.ParseInt(fields[1], 10, 64)
		cpuTime, cpuTimeErr := parseCPUTime(fields[2])
		if cpuErr != nil || rssErr != nil || cpuTimeErr != nil {
			return nil, fmt.Errorf("parse ps output %q", strings.TrimSpace(string(output)))
		}
		samples = append(samples, processSample{
			ObservedAt:     time.Now().UTC().Format(time.RFC3339Nano),
			CPUPercent:     cpu,
			CPUTimeSeconds: cpuTime,
			RSSBytes:       rssKB * 1024,
		})
		if !time.Now().Before(deadline) {
			break
		}
		sleep := interval
		if remaining := time.Until(deadline); remaining < sleep {
			sleep = remaining
		}
		if sleep > 0 {
			time.Sleep(sleep)
		}
	}
	return samples, nil
}

func parseCPUTime(value string) (float64, error) {
	dayParts := strings.Split(value, "-")
	if len(dayParts) > 2 {
		return 0, fmt.Errorf("invalid CPU time %q", value)
	}
	days := 0
	timePart := dayParts[0]
	if len(dayParts) == 2 {
		parsedDays, err := strconv.Atoi(dayParts[0])
		if err != nil {
			return 0, fmt.Errorf("parse CPU days: %w", err)
		}
		days = parsedDays
		timePart = dayParts[1]
	}

	parts := strings.Split(timePart, ":")
	if len(parts) < 2 || len(parts) > 3 {
		return 0, fmt.Errorf("invalid CPU time %q", value)
	}
	seconds, err := strconv.ParseFloat(parts[len(parts)-1], 64)
	if err != nil {
		return 0, fmt.Errorf("parse CPU seconds: %w", err)
	}
	minutes, err := strconv.Atoi(parts[len(parts)-2])
	if err != nil {
		return 0, fmt.Errorf("parse CPU minutes: %w", err)
	}
	hours := 0
	if len(parts) == 3 {
		hours, err = strconv.Atoi(parts[0])
		if err != nil {
			return 0, fmt.Errorf("parse CPU hours: %w", err)
		}
	}
	return float64(days*86_400+hours*3_600+minutes*60) + seconds, nil
}

func cpuTimeAverage(samples []processSample) float64 {
	if len(samples) < 2 {
		return math.NaN()
	}
	first := samples[0]
	last := samples[len(samples)-1]
	firstAt, firstErr := time.Parse(time.RFC3339Nano, first.ObservedAt)
	lastAt, lastErr := time.Parse(time.RFC3339Nano, last.ObservedAt)
	elapsed := lastAt.Sub(firstAt).Seconds()
	used := last.CPUTimeSeconds - first.CPUTimeSeconds
	if firstErr != nil || lastErr != nil || elapsed <= 0 || used < 0 {
		return math.NaN()
	}
	return used / elapsed * 100
}

func firstCold(samples []revealSample) revealSample {
	for _, sample := range samples {
		if !sample.Warm {
			return sample
		}
	}
	return revealSample{}
}

func percentile(values []float64, p float64) float64 {
	if len(values) == 0 {
		return math.NaN()
	}
	sorted := append([]float64(nil), values...)
	sort.Float64s(sorted)
	index := int(math.Ceil(p*float64(len(sorted)))) - 1
	if index < 0 {
		index = 0
	}
	if index >= len(sorted) {
		index = len(sorted) - 1
	}
	return sorted[index]
}

func average(values []float64) float64 {
	if len(values) == 0 {
		return math.NaN()
	}
	var total float64
	for _, value := range values {
		total += value
	}
	return total / float64(len(values))
}

func maximum(values []float64) float64 {
	if len(values) == 0 {
		return math.NaN()
	}
	value := values[0]
	for _, candidate := range values[1:] {
		if candidate > value {
			value = candidate
		}
	}
	return value
}

func displayTopology() string {
	text := commandOutput("system_profiler", "SPDisplaysDataType")
	var selected []string
	for _, line := range strings.Split(text, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "Display Type:") ||
			strings.HasPrefix(trimmed, "Resolution:") ||
			strings.HasPrefix(trimmed, "Main Display:") ||
			strings.HasPrefix(trimmed, "Online:") {
			selected = append(selected, trimmed)
		}
	}
	return strings.Join(selected, "; ")
}

func commandOutput(name string, args ...string) string {
	output, err := exec.Command(name, args...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func userHome() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "."
	}
	return home
}

func fatal(message string) {
	fmt.Fprintln(os.Stderr, "perf-check:", message)
	os.Exit(2)
}
