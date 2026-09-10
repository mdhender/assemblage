// Copyright (c) 2026 Michael D Henderson.

// Package edge holds the two things everything at the HTTP edge must agree on.
//
// DESIGN.md 14 says mapping a domain error to an HTTP status happens "only at
// the transport edge, in one function", and DESIGN.md 12's session cookie is
// written by "one cookie-writing path in the process, not two". A second copy
// of either would be a second policy: two functions that disagree about what
// "conflict" means, or a second cookie that is missing Secure (invariant 13).
//
// The HTML UI this package was extracted for is gone (issue #3), and it stays
// because the second writer does: internal/api issues the session cookie and
// internal/devroutes issues one too, so "one cookie-writing path" is still a
// rule with something to enforce.
//
// A sibling import would have been the other answer, and the design rejects it
// for the same reason internal/reqctx exists: api, devroutes and server agree
// about a value by importing a leaf, never one another (DESIGN.md 4). So this
// package is a leaf. It imports the standard library and internal/{domain,config}
// and nothing else, holds no state, and must never grow a third
// responsibility -- a package named for "the edge" is a package everything at
// the edge would otherwise be tempted to put things in.
//
// It renders nothing. The problem document is internal/api's, because RFC 9457
// is the JSON API's contract. What is shared is the decision, not the
// presentation.
package edge
