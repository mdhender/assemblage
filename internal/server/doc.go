// Copyright (c) 2026 Michael D Henderson.

// Package server is the composition root for asmd. It owns exactly two things
// that have nowhere else to live:
//
//   - The route table. internal/api and internal/devroutes each own their
//     handlers; something has to decide which of them are mounted, and that
//     decision is the gate on the /__development/* routes (invariant 16).
//     Building the table is a function rather than a side effect of serving,
//     so that "asmd routes" prints the table the running configuration
//     actually produces instead of a second list that can drift from it.
//   - The one graceful-shutdown path (invariant 17), reached by SIGTERM, by
//     --timeout expiry, and by the development shutdown route alike.
//
// It holds no business logic: it mounts handlers and nothing more.
//
// Permitted imports: internal/config, internal/api, internal/devroutes,
// internal/edge, internal/render. Never internal/store or internal/domain
// directly.
package server
