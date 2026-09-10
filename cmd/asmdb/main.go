// Copyright (c) 2026 Michael D Henderson.

// Command asmdb initialises, migrates, bootstraps, seeds, and checks the
// database (DESIGN.md 11).
//
// --db names a directory that must already exist, and the database inside it is
// always assemblage.db. asmdb never creates a directory: a missing DIR is a
// hard failure naming the directory, in every subcommand including init
// (invariant 19). init is the only subcommand permitted to create the database
// file, and asmdb is the only command permitted to migrate one (invariant 20).
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
	"github.com/mdhender/assemblage/internal/store"
	"github.com/spf13/cobra"
)

const program = "asmdb"

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
		Short:         "Create, migrate, and check the assemblage database",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.AddCommand(&cobra.Command{
		Use:   "version",
		Short: "Print the version, commit, and Go version",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			fmt.Fprintln(cmd.OutOrStdout(), assemblage.VersionString(program))
			return nil
		},
	})
	root.AddCommand(
		newInitCmd(),
		newMigrateCmd(),
		newBootstrapCmd(),
		newSeedCmd(),
		newCheckCmd(),
		newBackupCmd(),
		newVacuumCmd(),
	)
	return root
}

// addDBFlag gives a subcommand the --db flag, which every subcommand has and
// none may do without.
//
// It names a directory, never a file. The database inside it is the constant
// assemblage.db, so --db cannot address two different files depending on which
// subcommand was typed (DESIGN.md 13.1).
func addDBFlag(cmd *cobra.Command, dir *string) {
	cmd.Flags().StringVar(dir, "db", "", fmt.Sprintf("directory holding %s; it must already exist", store.FileName))
	_ = cmd.MarkFlagRequired("db")
}
