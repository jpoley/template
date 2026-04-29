// Single source of truth for the basePath. Imported by:
//  - next.config.ts (Next.js basePath setting)
//  - middleware.ts (strip the prefix at proxy time)
//  - lib/api.ts (browser-side fetch base)
// Changing this constant updates all three together.
export const BASE_PATH = '/internal'
