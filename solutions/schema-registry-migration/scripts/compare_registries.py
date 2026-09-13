#!/usr/bin/env python3
"""Compare the source Schema Registry with the Schema Registry of the Redpanda
shadow cluster, subject by subject.

For every subject on the source, the destination must hold the same versions,
the same global schema IDs, the same schema type, the same subject-level
compatibility setting (or none), and the same references on the latest
version. Extra subjects that exist only on the destination are listed but are
not a mismatch: after cutover, applications register new schemas there.

By default the script polls until the two registries agree or TIMEOUT
seconds pass (replication is asynchronous: a new subject arrives with the
next full sync). Pass --once to compare a single time. Exit code 0 means they
agree; 1 means they do not. Runs inside the client container (`make compare`).
"""
import os
import sys
import time

import requests

SOURCE = os.environ.get("SOURCE_SR_URL", "http://confluent-schema-registry:8081")
DEST = os.environ.get("SHADOW_SR_URL", "http://redpanda:8081")
TIMEOUT = int(os.environ.get("TIMEOUT", "120"))


def get(base, path):
    resp = requests.get(f"{base}{path}", timeout=10)
    if resp.status_code == 404:
        return None
    resp.raise_for_status()
    return resp.json()


def subjects(base):
    return sorted(get(base, "/subjects") or [])


def compatibility(base, subject):
    body = get(base, f"/config/{subject}")
    if body is None:
        return "(inherits global)"
    return body.get("compatibilityLevel", "?")


# tag::describe[]
def describe(base, subject):
    """One comparable record for a subject: versions, schema IDs, type,
    compatibility, and the references of the latest version."""
    versions = get(base, f"/subjects/{subject}/versions") or []
    ids = []
    latest = {}
    for v in versions:
        latest = get(base, f"/subjects/{subject}/versions/{v}") or {}
        ids.append(latest.get("id"))
    refs = [f'{r["subject"]}@{r["version"]}' for r in latest.get("references", [])]
    return {
        "versions": versions,
        "ids": ids,
        "type": latest.get("schemaType", "AVRO") if latest else "-",
        "compatibility": compatibility(base, subject),
        "references": refs,
    }
# end::describe[]


def fmt(record):
    return " ".join(
        [
            f'versions={",".join(map(str, record["versions"])) or "-"}',
            f'ids={",".join(map(str, record["ids"])) or "-"}',
            f'type={record["type"]}',
            f'compatibility={record["compatibility"]}',
            f'references={",".join(record["references"]) or "-"}',
        ]
    )


def compare():
    src_subjects = subjects(SOURCE)
    dst_subjects = subjects(DEST)
    rows = []
    agree = True
    for s in src_subjects:
        src = describe(SOURCE, s)
        dst = describe(DEST, s) if s in dst_subjects else None
        match = dst == src
        agree = agree and match
        rows.append((s, src, dst, match))
    extra = [s for s in dst_subjects if s not in src_subjects]
    return agree, rows, extra


def main():
    once = "--once" in sys.argv
    deadline = time.time() + TIMEOUT
    while True:
        agree, rows, extra = compare()
        if agree or once or time.time() >= deadline:
            break
        time.sleep(2)

    print(f"source      {SOURCE}")
    print(f"destination {DEST}")
    print()
    for subject, src, dst, match in rows:
        print(f"{'match' if match else 'MISMATCH':<9}{subject}")
        print(f"         source:      {fmt(src)}")
        print(f"         destination: {fmt(dst) if dst else '(missing)'}")
    for s in extra:
        print(f"{'dest only':<9}{s}")
        print(f"         destination: {fmt(describe(DEST, s))}")
    print()
    if agree:
        print(f"source and destination agree on {len(rows)} subject(s)")
        return 0
    print(f"source and destination differ (waited up to {TIMEOUT}s)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
