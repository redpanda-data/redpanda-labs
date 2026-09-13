#!/usr/bin/env bash
# Scaffold a new solution from templates/solution.
#
#   tools/new-solution.sh <slug>
#
# Creates solutions/<slug>/ (code, Makefile, compose file, verify script,
# Doc Detective specs) and docs/modules/<slug>/ (overview + step page,
# images, partials) with relative symlinks so the docs build reads the code
# straight from solutions/<slug>/:
#
#   docs/modules/<slug>/examples                        -> ../../../solutions/<slug>
#   docs/modules/<slug>/attachments/docker-compose.yml   -> ../../../../solutions/<slug>/docker-compose.yml
#   docs/modules/<slug>/attachments/env.example          -> ../../../../solutions/<slug>/.env.example
#   docs/modules/<slug>/attachments/Makefile.mk          -> ../../../../solutions/<slug>/Makefile
#   docs/modules/<slug>/attachments/scripts/verify.sh    -> ../../../../../solutions/<slug>/scripts/verify.sh
#   docs/modules/<slug>/attachments/scripts/verify-lib.sh -> ../../../../../tools/verify-lib.sh
#
# The slug is the directory name, the Antora module name, and the solution id.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/lib.sh"
slug=${1:-}

usage() { sed -n '2,18p' "$0"; }

if [ -z "$slug" ] || [ "$slug" = "-h" ] || [ "$slug" = "--help" ]; then
  usage
  exit 2
fi

if ! valid_slug "$slug"; then
  echo "new-solution: '$slug' is not a valid slug (lowercase letters, digits, hyphens; 1-64 chars; no leading or trailing hyphen)" >&2
  exit 1
fi
if is_reserved "$slug"; then
  echo "new-solution: '$slug' is a reserved id ($RESERVED_IDS)" >&2
  exit 1
fi
if [ -e "$root/solutions/$slug" ] || [ -e "$root/docs/modules/$slug" ]; then
  echo "new-solution: solutions/$slug or docs/modules/$slug already exists" >&2
  exit 1
fi

template="$root/templates/solution"
[ -d "$template/code" ] && [ -d "$template/docs-module" ] || { echo "new-solution: $template is incomplete" >&2; exit 1; }

title=$(printf '%s' "$slug" | perl -pe 's/(^|-)([a-z0-9])/($1 eq "-" ? " " : "") . uc($2)/ge')

code="$root/solutions/$slug"
module="$root/docs/modules/$slug"

mkdir -p "$code" "$module"
cp -R "$template/code/." "$code/"
cp -R "$template/docs-module/." "$module/"
mkdir -p "$module/images" "$module/partials" "$module/attachments/scripts"
touch "$module/images/.gitkeep" "$module/partials/.gitkeep"

# Relative symlinks. Depth matters: attachments/ is four levels below the root.
# Antora silently drops dotfiles and files without an extension, so .env.example
# publishes as env.example and Makefile as Makefile.mk (readers rename them).
ln -s "../../../solutions/$slug" "$module/examples"
ln -s "../../../../solutions/$slug/docker-compose.yml" "$module/attachments/docker-compose.yml"
ln -s "../../../../solutions/$slug/.env.example" "$module/attachments/env.example"
ln -s "../../../../solutions/$slug/Makefile" "$module/attachments/Makefile.mk"
ln -s "../../../../../solutions/$slug/scripts/verify.sh" "$module/attachments/scripts/verify.sh"
# verify.sh sources verify-lib.sh from tools/; publish it next to the script so
# build-along readers get a working pair.
ln -s "../../../../../tools/verify-lib.sh" "$module/attachments/scripts/verify-lib.sh"

# Fill placeholders in every regular text file that was copied.
find "$code" "$module" -type f \( -name '*.adoc' -o -name '*.md' -o -name '*.yml' -o -name '*.yaml' -o -name '*.json' -o -name '*.sh' -o -name 'Makefile' -o -name '.env.example' \) -print0 \
  | xargs -0 perl -pi -e "s/__slug__/$slug/g; s/__title__/$title/g"

chmod +x "$code/scripts/"*.sh

# Symlink sanity check.
broken=0
while IFS= read -r l; do
  if ! [ -e "$l" ]; then echo "new-solution: broken symlink $l" >&2; broken=1; fi
done < <(find "$module" -type l)
[ $broken -eq 0 ]

cat <<MSG
Created solution '$slug' ($title)

  solutions/$slug/               code, compose file, Makefile, scripts/verify.sh, tests/doc-detective/
  docs/modules/$slug/pages/      index.adoc (overview) and step.adoc (rename per step id)

Next steps
  1. Edit docs/modules/$slug/pages/index.adoc: fill every attribute and section.
  2. Rename pages/step.adoc and tests/doc-detective/specs/step.json (file, specId, testId)
     to your first step id, copy them for each further step, and list the ids in
     :page-solution-steps:.
  3. Put real services, sample data, and checks in solutions/$slug/; make scripts/verify.sh
     prove the outcome.
  4. Run tools/check-metadata.sh, then 'make up seed verify' inside solutions/$slug/.
MSG
