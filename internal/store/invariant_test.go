// Copyright (c) 2026 Michael D Henderson.

package store

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// DESIGN.md 13.1 says the database file name is a constant in this package,
// enforced over the source tree the way internal/workflow enforces its own
// single writer: a grep for the name finds it only where it belongs.
//
// The rule is not about tidiness. A caller that spells the name out is a
// second answer to "what is the file called", and the two only have to
// disagree once -- a test that joins the wrong name does not fail loudly, it
// creates a stray file beside the real one and passes. Callers that want a
// path use Path; callers that want the name for help text or a message use
// FileName.
//
// Two files are exempt and both are deliberate. This package defines the
// constant, and cmd/asmd/storage_test.go pins it: one assertion holds the
// value, everything else derives it.

// dbName matches the file name in a Go string literal. It is deliberately
// insensitive to what surrounds it -- what is being caught is somebody typing
// the name again, and somebody typing it again will not format it like this.
var dbName = regexp.MustCompile(`"[^"]*assemblage\.db`)

// exempt are the paths permitted to spell the name out, relative to the
// repository root and slash-separated.
var exempt = map[string]bool{
	"internal/store/store.go":          true, // the definition
	"cmd/asmd/storage_test.go":         true, // the test that pins it
	"internal/store/invariant_test.go": true, // this file, which quotes it
}

// TestNothingElseSpellsTheDatabaseName is DESIGN.md 13.1 as an assertion.
func TestNothingElseSpellsTheDatabaseName(t *testing.T) {
	var offenders []string
	for path, src := range goSources(t) {
		if exempt[path] {
			continue
		}
		for line := range strings.SplitSeq(src, "\n") {
			code, _, _ := strings.Cut(line, "//")
			if dbName.MatchString(code) {
				offenders = append(offenders, path+": "+strings.TrimSpace(line))
			}
		}
	}
	sort.Strings(offenders)
	if len(offenders) > 0 {
		t.Errorf("the database file name is spelled out in %d place(s) outside internal/store:\n\t%s\n\n"+
			"Use store.Path(dir) for a path, or store.FileName for the name alone (DESIGN.md 13.1).",
			len(offenders), strings.Join(offenders, "\n\t"))
	}
}

// goSources returns every .go file under cmd/ and internal/, keyed by its path
// relative to the repository root.
//
// Unlike internal/workflow's copy it keeps _test.go files, because tests are
// where a hand-rolled path is most likely to be written and least likely to be
// noticed.
func goSources(t *testing.T) map[string]string {
	t.Helper()

	root, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]string{}
	for _, dir := range []string{"cmd", "internal"} {
		err := filepath.WalkDir(filepath.Join(root, dir), func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() || !strings.HasSuffix(path, ".go") {
				return nil
			}
			b, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			rel, err := filepath.Rel(root, path)
			if err != nil {
				return err
			}
			out[filepath.ToSlash(rel)] = string(b)
			return nil
		})
		if err != nil {
			t.Fatalf("walking %s: %v", dir, err)
		}
	}
	return out
}
