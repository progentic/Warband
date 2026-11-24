package model

import "core:crypto/sha2"

// The string literal owns the canonical bytes for the lifetime of the binary.
CatalogEntry :: struct {
	id: Catalog_Id,
	payload: string,
}
CatalogRevision :: u32(1)
CatalogV1 :: [?]CatalogEntry{{1, ""}, {2, "abc"}}
CatalogLimit :: 32

catalog_digest :: proc(payload: string) -> (digest: [32]u8) {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, transmute([]byte)payload)
	sha2.final(&ctx, digest[:])
	return
}

valid_catalog :: proc(entries: []CatalogEntry) -> bool {
	if len(entries) == 0 || len(entries) > CatalogLimit { return false }
	digests: [CatalogLimit][32]u8
	for entry, i in entries {
		if entry.id == 0 || len(entry.payload) > MAX_PAYLOAD_BYTES { return false }
		digests[i] = catalog_digest(entry.payload)
		for earlier, j in entries[:i] {
			if entry.id == earlier.id || entry.payload == earlier.payload || digests[i] == digests[j] { return false }
		}
	}
	return true
}

catalog_entry :: proc(revision: u32, id: Catalog_Id) -> (CatalogEntry, bool) {
	if revision != CatalogRevision { return {}, false }
	for entry in CatalogV1 {
		if entry.id == id { return entry, true }
	}
	return {}, false
}
