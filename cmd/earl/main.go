// Copyright (c) 2026 Michael D Henderson.

// Command earl exercises the API from the command line (DESIGN.md 11).
//
// It is a first-class client and the acceptance-test harness for every
// milestone, not a debug toy: if earl cannot do it, the API is incomplete.
//
// It points at the public origin rather than at the Go listener, so that it
// exercises the proxy hop that exists in production. Talking to
// 127.0.0.1:18443 directly bypasses the proxy and exercises a path that does
// not exist there (DESIGN.md 11).
//
// This file is flags and wiring. Behaviour lives in internal/.
package main

import (
	"fmt"
	"os"

	"github.com/mdhender/assemblage"
	"github.com/mdhender/assemblage/internal/buildenv"
	"github.com/mdhender/assemblage/internal/config"
	"github.com/mdhender/assemblage/internal/dotenv"
	"github.com/spf13/cobra"
)

const program = "earl"

func main() {
	// ASSEMBLAGE_ENV selects which dotenv files load, and scopes the credential
	// file. It is read before flag parsing because those files populate the
	// environment we read, and it is resolved by internal/config so that the
	// variable is named in one place. An unset, empty, or misspelled value
	// resolves to production (DESIGN.md 14): the value that loads a
	// developer's .env has to be the one somebody wrote down.
	env := config.Resolve(config.Inputs{Env: config.FromEnv()}).Environment
	// Load also rejects an unknown environment, which is what lets env be used
	// as a path segment in the credential file without further checking.
	if err := dotenv.Load(env.String()); err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", program, err)
		os.Exit(1)
	}
	// Called explicitly, from main, never from init (invariant 18).
	buildenv.Verify()

	if err := newRootCmd().Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", program, err)
		os.Exit(1)
	}
}

func newRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:           program,
		Short:         "Exercise the assemblage API from the command line",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.AddCommand(newLoginCmd(), newLogoutCmd(), newWhoamiCmd(), newAdminCmd(), newDocCmd(), newQueueCmd(), newJobCmd())
	root.AddCommand(newSiteCmd(), newCategoryCmd(), newChannelCmd(), newElementTypeCmd())
	root.AddCommand(newAlertCmd(), newNotificationCmd())
	root.AddCommand(newInviteCmd(), newUserCmd())
	root.AddCommand(&cobra.Command{
		Use:   "version",
		Short: "Print the version, commit, and Go version",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			fmt.Fprintln(cmd.OutOrStdout(), assemblage.VersionString(program))
			return nil
		},
	})
	return root
}
