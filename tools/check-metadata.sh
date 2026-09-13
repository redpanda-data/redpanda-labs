#!/usr/bin/env bash
# Validate the metadata contract for every solution in this repo.
#
#   tools/check-metadata.sh            check every docs/modules/<slug>/pages/index.adoc
#   tools/check-metadata.sh <slug>...  check only these
#
# Checks (errors fail the run, warnings do not):
#   - module name is a valid, non-reserved slug and solutions/<slug>/ exists
#   - overview has :page-layout: solution and :page-topic-type: solution
#   - :page-solution-version: matches ^v[0-9]+\.[0-9]+\.[0-9]+$
#   - difficulty, status, download, platforms, duration, featured are valid
#   - deprecated solutions name :page-solution-superseded-by:
#   - every :page-solution-steps: id has pages/<id>.adoc (with :page-layout: solution-step)
#     and solutions/<slug>/tests/doc-detective/specs/<id>.json, and every non-index
#     page is listed in the steps (strict bijection)
#   - no template placeholders are left ([...], __x__, vX.Y.Z, the step id "step")
#   - every symlink under docs/modules/<slug>/ resolves
#   - solutions/<slug>/ has docker-compose.yml, Makefile, .env.example, scripts/verify.sh,
#     tests/doc-detective/.doc-detective.json, specs/_setup.json, specs/_teardown.json
#   - :page-categories: values exist in valid-categories.yml when it is reachable:
#     VALID_CATEGORIES_PATH=<file>, or a GITHUB_TOKEN / GH_TOKEN that can read
#     redpanda-data/docs. Otherwise the category check is skipped with a notice.
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

errors=0
warnings=0
reserved="progress download api index ROOT"

err()    { errors=$((errors + 1));     printf 'ERROR  %s: %s\n' "$1" "$2"; }
warn()   { warnings=$((warnings + 1)); printf 'WARN   %s: %s\n' "$1" "$2"; }
notice() { printf 'NOTICE %s\n' "$1"; }

in_list() {
  local needle=$1
  shift
  for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
  return 1
}

trim() { printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

# header <file>: the attribute lines of the document header (title to first blank line)
header() { awk 'NR==1 && /^= /{next} /^[[:space:]]*$/{exit} /^:[A-Za-z0-9_-]+:/{print}' "$1"; }
# attr <header> <name>
attr() { printf '%s\n' "$1" | sed -nE "s/^:$2:[[:space:]]*//p" | head -1 | sed -E 's/[[:space:]]+$//'; }
has_attr() { printf '%s\n' "$1" | grep -qE "^:$2:"; }

is_placeholder() {
  case "$1" in
    *__*__*|\[*\]|*"[...]"*|vX.Y.Z) return 0 ;;
  esac
  return 1
}

# Category list --------------------------------------------------------------
VALID_CATS=""
CATS_AVAILABLE=0
load_categories() {
  local src="${VALID_CATEGORIES_PATH:-}"
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  local tmp
  if [ -z "$src" ] && [ -n "$token" ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/valid-categories.XXXXXX")
    if curl -fsSL -H "Authorization: Bearer $token" -H "Accept: application/vnd.github.raw" \
        "https://api.github.com/repos/redpanda-data/docs/contents/shared/modules/ROOT/partials/valid-categories.yml" -o "$tmp"; then
      src=$tmp
    else
      notice "could not fetch valid-categories.yml from redpanda-data/docs with the given token; category check skipped"
      rm -f "$tmp"
      return
    fi
  fi
  if [ -z "$src" ]; then
    notice "category check skipped: set VALID_CATEGORIES_PATH or GITHUB_TOKEN to enable it"
    return
  fi
  if [ ! -r "$src" ]; then
    notice "category check skipped: $src is not readable"
    return
  fi
  VALID_CATS=$(sed -nE "s/^[[:space:]]*-[[:space:]]*category:[[:space:]]*'?([^']*[^' ])'?[[:space:]]*$/\1/p" "$src")
  if [ -z "$VALID_CATS" ]; then
    notice "category check skipped: no categories parsed from $src"
    return
  fi
  CATS_AVAILABLE=1
}
valid_category() { printf '%s\n' "$VALID_CATS" | grep -qxF "$1"; }

load_categories

# Which slugs ------------------------------------------------------------------
if [ $# -gt 0 ]; then
  slugs="$*"
else
  slugs=$( { ls -1 docs/modules 2>/dev/null; ls -1 solutions 2>/dev/null; } | grep -v '^ROOT$' | sort -u )
fi

if [ -z "$slugs" ]; then
  notice "no solutions found under docs/modules or solutions/"
fi

for slug in $slugs; do
  module="docs/modules/$slug"
  code="solutions/$slug"
  page="$module/pages/index.adoc"

  if ! [[ "$slug" =~ ^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$ ]]; then
    err "$slug" "not a valid slug (lowercase letters, digits, hyphens, 1-64 chars)"
  fi
  if in_list "$slug" $reserved; then
    err "$slug" "reserved id (one of: $reserved)"
  fi
  if [ ! -d "$module" ]; then
    err "$code" "has no docs module docs/modules/$slug"
    continue
  fi
  if [ ! -d "$code" ]; then
    err "$module" "has no code directory solutions/$slug"
  fi
  if [ ! -f "$page" ]; then
    err "$module" "missing pages/index.adoc (the overview)"
    continue
  fi

  h=$(header "$page")

  # Layout and topic type
  [ "$(attr "$h" page-layout)" = "solution" ] || err "$page" ":page-layout: must be 'solution' (got '$(attr "$h" page-layout)')"
  [ "$(attr "$h" page-topic-type)" = "solution" ] || err "$page" ":page-topic-type: must be 'solution'"

  # Placeholders in any attribute value
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name=$(printf '%s' "$line" | sed -nE 's/^:([A-Za-z0-9_-]+):.*/\1/p')
    value=$(trim "$(printf '%s' "$line" | sed -E 's/^:[A-Za-z0-9_-]+:[[:space:]]*//')")
    if is_placeholder "$value"; then
      err "$page" ":$name: still holds the template placeholder '$value'"
    fi
  done <<< "$h"

  # Description
  desc=$(attr "$h" description)
  if [ -z "$desc" ]; then
    err "$page" ":description: is required"
  elif [ "${#desc}" -gt 200 ]; then
    warn "$page" ":description: is ${#desc} chars (keep it at 200 or fewer)"
  fi

  # Version
  version=$(attr "$h" page-solution-version)
  if [ -z "$version" ]; then
    err "$page" ":page-solution-version: is required (vX.Y.Z)"
  elif ! [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    err "$page" ":page-solution-version: '$version' must match vX.Y.Z (for example v1.0.0)"
  fi

  # Enums
  difficulty=$(attr "$h" page-solution-difficulty)
  in_list "$difficulty" beginner intermediate advanced || err "$page" ":page-solution-difficulty: '$difficulty' must be beginner, intermediate, or advanced"

  status=$(attr "$h" page-solution-status)
  in_list "$status" draft published deprecated || err "$page" ":page-solution-status: '$status' must be draft, published, or deprecated"
  if [ "$status" = "deprecated" ] && [ -z "$(attr "$h" page-solution-superseded-by)" ]; then
    err "$page" "deprecated solutions must set :page-solution-superseded-by:"
  fi

  download=$(attr "$h" page-solution-download)
  in_list "$download" authenticated public none || err "$page" ":page-solution-download: '$download' must be authenticated, public, or none"

  duration=$(attr "$h" page-solution-duration)
  if ! [[ "$duration" =~ ^[0-9]+$ ]] || [ "$duration" -lt 5 ] || [ "$duration" -gt 600 ]; then
    err "$page" ":page-solution-duration: '$duration' must be an integer number of minutes between 5 and 600"
  fi

  if has_attr "$h" page-solution-featured; then
    [ "$(attr "$h" page-solution-featured)" = "true" ] || err "$page" ":page-solution-featured: may only be 'true' (omit it otherwise)"
  fi

  platforms=$(attr "$h" page-solution-platforms)
  if [ -n "$platforms" ]; then
    IFS=',' read -ra plist <<< "$platforms"
    for p in "${plist[@]}"; do
      p=$(trim "$p")
      in_list "$p" self-managed cloud || err "$page" ":page-solution-platforms: '$p' must be self-managed or cloud"
    done
  fi

  [ -n "$(attr "$h" page-solution-technologies)" ] || err "$page" ":page-solution-technologies: is required"

  # Categories
  categories=$(attr "$h" page-categories)
  if [ -z "$categories" ]; then
    err "$page" ":page-categories: is required"
  elif [ $CATS_AVAILABLE -eq 1 ]; then
    IFS=',' read -ra clist <<< "$categories"
    for c in "${clist[@]}"; do
      c=$(trim "$c")
      valid_category "$c" || err "$page" ":page-categories: '$c' is not in valid-categories.yml"
    done
  fi

  has_attr "$h" page-solution-related-docs || warn "$page" "no :page-solution-related-docs: (the overview should link the canonical Product Docs pages)"

  # Steps: every id has a page and a spec; every non-index page is a step
  steps_raw=$(attr "$h" page-solution-steps)
  if [ -z "$steps_raw" ]; then
    err "$page" ":page-solution-steps: is required (ordered, comma separated step ids)"
  else
    IFS=',' read -ra steps <<< "$steps_raw"
    listed=""
    for s in "${steps[@]}"; do
      s=$(trim "$s")
      [ -n "$s" ] || continue
      listed="$listed $s"
      if [ "$s" = "step" ]; then
        err "$page" "step id 'step' is the template placeholder: rename pages/step.adoc and specs/step.json to the real step id"
      fi
      if ! [[ "$s" =~ ^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$ ]]; then
        err "$page" "step id '$s' is not a valid slug"
      fi
      if in_list "$s" $reserved; then
        err "$page" "step id '$s' is reserved"
      fi
      sp="$module/pages/$s.adoc"
      if [ ! -f "$sp" ]; then
        err "$page" "step '$s' has no page $sp"
      else
        sh=$(header "$sp")
        [ "$(attr "$sh" page-layout)" = "solution-step" ] || err "$sp" ":page-layout: must be 'solution-step'"
        [ -n "$(attr "$sh" description)" ] || warn "$sp" "no :description:"
        sdur=$(attr "$sh" page-solution-step-duration)
        if [ -n "$sdur" ] && ! [[ "$sdur" =~ ^[0-9]+$ ]]; then
          err "$sp" ":page-solution-step-duration: '$sdur' must be an integer number of minutes"
        fi
      fi
      spec="$code/tests/doc-detective/specs/$s.json"
      [ -f "$spec" ] || err "$page" "step '$s' has no Doc Detective spec $spec"
    done
    for f in "$module"/pages/*.adoc; do
      [ -e "$f" ] || continue
      stem=$(basename "$f" .adoc)
      [ "$stem" = "index" ] && continue
      in_list "$stem" $listed || err "$f" "page is not listed in :page-solution-steps: (every non-index page must be a step)"
    done
  fi

  # Symlinks
  while IFS= read -r l; do
    [ -e "$l" ] || err "$l" "symlink target '$(readlink "$l")' does not exist"
  done < <(find "$module" -type l 2>/dev/null)

  # Required code files
  if [ -d "$code" ]; then
    for f in docker-compose.yml Makefile .env.example scripts/verify.sh README.md \
             tests/doc-detective/.doc-detective.json tests/doc-detective/specs/_setup.json tests/doc-detective/specs/_teardown.json; do
      [ -f "$code/$f" ] || err "$code" "missing $f"
    done
    [ -x "$code/scripts/verify.sh" ] || { [ -f "$code/scripts/verify.sh" ] && err "$code/scripts/verify.sh" "is not executable"; }
    for spec in "$code"/tests/doc-detective/specs/*.json; do
      [ -e "$spec" ] || continue
      if command -v jq >/dev/null; then
        jq -e . "$spec" >/dev/null 2>&1 || err "$spec" "is not valid JSON"
      elif command -v python3 >/dev/null; then
        python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$spec" 2>/dev/null || err "$spec" "is not valid JSON"
      fi
    done
  fi
done

printf '\ncheck-metadata: %d error(s), %d warning(s)\n' "$errors" "$warnings"
[ "$errors" -eq 0 ]
