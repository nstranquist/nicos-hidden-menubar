package main

import (
	"math"
	"testing"
)

func TestParseCPUTime(t *testing.T) {
	cases := map[string]float64{
		"0:01.30":       1.30,
		"12:34.56":      754.56,
		"1:02:03.40":    3_723.40,
		"2-01:02:03.40": 176_523.40,
	}
	for input, expected := range cases {
		actual, err := parseCPUTime(input)
		if err != nil {
			t.Fatalf("parseCPUTime(%q): %v", input, err)
		}
		if math.Abs(actual-expected) > 0.0001 {
			t.Errorf("parseCPUTime(%q) = %f, want %f", input, actual, expected)
		}
	}
}

func TestCPUTimeAverage(t *testing.T) {
	samples := []processSample{
		{
			ObservedAt:     "2026-07-29T22:00:00Z",
			CPUTimeSeconds: 10.00,
		},
		{
			ObservedAt:     "2026-07-29T22:05:00Z",
			CPUTimeSeconds: 10.03,
		},
	}
	actual := cpuTimeAverage(samples)
	expected := 0.01
	if math.Abs(actual-expected) > 0.0001 {
		t.Fatalf("cpuTimeAverage() = %f, want %f", actual, expected)
	}
}

func TestCPUTimeAverageRejectsCounterRegression(t *testing.T) {
	samples := []processSample{
		{
			ObservedAt:     "2026-07-29T22:00:00Z",
			CPUTimeSeconds: 10,
		},
		{
			ObservedAt:     "2026-07-29T22:05:00Z",
			CPUTimeSeconds: 9,
		},
	}
	if !math.IsNaN(cpuTimeAverage(samples)) {
		t.Fatal("cpuTimeAverage should reject a decreasing CPU counter")
	}
}
