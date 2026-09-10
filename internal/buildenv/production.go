// Copyright (c) 2026 Michael D Henderson.

//go:build production

package buildenv

import (
	"fmt"
	"os"
)

// Verify panics unless ASSEMBLAGE_ENV is exported as exactly "production".
//
// A release binary requires the value to be set explicitly, because a server
// should say what it is.
func Verify() {
	if v := os.Getenv("ASSEMBLAGE_ENV"); v != "production" {
		panic(fmt.Sprintf(
			"buildenv: built with -tags production, which requires ASSEMBLAGE_ENV=production; got %q", v))
	}
}
