#!/usr/bin/env python3
"""Run the light calibration sweep described in the lab README and write a CSV.

Must be run from the simple-client directory (docker compose context), with
the stack already up and the quota-demo topic already created. Re-seeds a
fresh backlog before every trial so each one starts from the same conditions.
"""
import csv
import random
import re
import subprocess
import sys
import time

TOPIC = "quota-demo"
RECORD_SIZE = 1700
NUM_RECORDS = 300_000  # ~510MB backlog per trial
# The quota lets one burst through almost instantly, then the connection can
# go silent for up to the full throttle-delay cap before the next one. A
# window shorter than that only sees one early burst and badly overstates
# the rate (active-window = that burst's own tiny duration). Default D_cap
# is 30s, so give every default-D_cap trial enough room for 3 full cycles.
DURATION_SEC = 95


def run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    if result.returncode != 0:
        print(f"WARN: {' '.join(cmd)} -> {result.returncode}: {result.stderr}", file=sys.stderr)
    return result.stdout


def seed() -> None:
    run(["docker", "compose", "exec", "-T", "python-client", "python3", "/scripts/client.py", "produce",
         "--topic", TOPIC, "--num-records", str(NUM_RECORDS), "--record-size-bytes", str(RECORD_SIZE),
         "--client-id", "seeder"])


def parse_output(out: str) -> tuple[float, float]:
    bps = re.search(r"bytes_per_sec=([0-9,]+)", out)
    rps = re.search(r"records_per_sec=([0-9,.]+)", out)
    return (
        float(bps.group(1).replace(",", "")) if bps else 0.0,
        float(rps.group(1).replace(",", "")) if rps else 0.0,
    )


def trial(row: dict, quota_r: float, consume_extra: list[str] = None) -> dict:
    client_id = f"calib-{row['track']}-{row['label']}-{int(quota_r)}-t{row['trial']}-{random.randint(0, 999999)}"
    reset_topic()  # every trial starts from an identical, clean backlog, avoiding cross-trial accumulation
    seed()
    run(["docker", "compose", "exec", "-T", "redpanda-0", "rpk", "cluster", "quotas", "alter",
         "--add", f"consumer_byte_rate={int(quota_r)}", "--add", f"producer_byte_rate={int(quota_r)}",
         "--name", f"client-id={client_id}"])
    cmd = ["docker", "compose", "exec", "-T", "python-client", "python3", "/scripts/client.py", "consume",
           "--topic", TOPIC, "--group-id", f"grp-{client_id}", "--duration-sec", str(row.get("duration", DURATION_SEC)),
           "--client-id", client_id]
    if consume_extra:
        cmd += consume_extra
    out = run(cmd)
    bps, rps = parse_output(out)
    row.update({"client_id": client_id, "quota_bytes_per_sec": quota_r, "bytes_per_sec": bps, "records_per_sec": rps,
                "overshoot_x": round(bps / quota_r, 1) if quota_r else 0.0})
    print(row)
    return row


def reset_topic() -> None:
    # A fresh consumer group reads from earliest-offset, and a brand-new quota
    # entity's token bucket starts full, so any backlog left over from
    # earlier testing can produce one huge, unthrottled initial burst that
    # dominates a short active-window measurement. Start every sweep from a
    # clean topic to avoid that.
    run(["docker", "compose", "exec", "-T", "redpanda-0", "rpk", "topic", "delete", TOPIC])
    run(["docker", "compose", "exec", "-T", "redpanda-0", "rpk", "topic", "create", TOPIC, "-p", "3"])


def main() -> None:
    reset_topic()
    rows: list[dict] = []

    # Fetch track: default vs. shrunk fetch-size settings, across R bracketing
    # both expected breakpoints.
    fetch_r_values = [5_000, 20_000, 80_000, 300_000, 1_000_000]
    fetch_configs = {
        "default": ["--fetch-max-bytes", "52428800", "--max-partition-fetch-bytes", "1048576"],
        "shrunk": ["--fetch-max-bytes", "1048576", "--max-partition-fetch-bytes", "65536"],
    }
    for label, extra in fetch_configs.items():
        for r in fetch_r_values:
            rows.append(trial({"track": "fetch", "label": label, "trial": 1}, r, extra))

    # D_cap confirmation: hold R fixed in the floor regime, vary the broker-wide
    # throttle delay cap. Duration scales with the cap so each run sees multiple
    # delay cycles, not just the initial full-bucket burst.
    for d_cap_ms, label in [(10_000, "10s"), (60_000, "60s")]:
        run(["docker", "compose", "exec", "-T", "redpanda-0", "rpk", "cluster", "config", "set",
             "max_kafka_throttle_delay_ms", str(d_cap_ms)])
        row = {"track": "dcap", "label": label, "trial": 1, "duration": max(DURATION_SEC, (d_cap_ms // 1000) * 3)}
        rows.append(trial(row, 20_000, fetch_configs["default"]))
    run(["docker", "compose", "exec", "-T", "redpanda-0", "rpk", "cluster", "config", "set",
         "max_kafka_throttle_delay_ms", "30000"])  # restore default

    with open("calibration.csv", "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["track", "label", "trial", "duration", "client_id",
                                                 "quota_bytes_per_sec", "bytes_per_sec", "records_per_sec",
                                                 "overshoot_x"])
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    print(f"\nwrote {len(rows)} rows to calibration.csv")


if __name__ == "__main__":
    main()
