#!/usr/bin/env python3
"""Predict actual observed throughput (A) for a given Redpanda client quota (R).

This model is derived from Redpanda's broker source. See the lab README for the
full derivation. The quota is a token bucket with capacity == rate == R
(the configured quota, bytes/sec). A full request up to S bytes (the
"slip-through size", bounded by the client's own fetch/batch settings) can
pass completely before any delay is computed. The resulting corrective delay
is capped at D_cap (max_kafka_throttle_delay_ms). This produces three
regimes, with a sharp breakpoint at R* = S / D_cap:

  - unconstrained (R very high): A is capped by the client's own request
    cadence rather than the quota.
  - nominal (R above the breakpoint): A is generally R.
  - floor (R below the breakpoint): A flattens out at S / D_cap and doesn't
    keep dropping as you lower R further.
"""
import argparse


def effective_slip_through_bytes(args: argparse.Namespace) -> tuple[int, bool]:
    if args.slip_through_bytes is not None:
        return args.slip_through_bytes, True
    if args.direction == "produce":
        return args.batch_size_bytes, False
    return min(args.fetch_max_bytes, args.max_partition_fetch_bytes * args.partitions), False


def predict(quota_bytes_per_sec: float, slip_through_bytes: int, throttle_delay_cap_sec: float,
            min_request_interval_sec: float) -> dict:
    delay = min(slip_through_bytes / quota_bytes_per_sec, throttle_delay_cap_sec)
    delay = max(delay, min_request_interval_sec)
    actual_bytes_per_sec = slip_through_bytes / delay

    unconstrained_breakpoint = slip_through_bytes / min_request_interval_sec
    breakpoint_bytes_per_sec = slip_through_bytes / throttle_delay_cap_sec
    if quota_bytes_per_sec >= unconstrained_breakpoint:
        regime = "unconstrained"
    elif quota_bytes_per_sec >= breakpoint_bytes_per_sec:
        regime = "nominal"
    else:
        regime = "floor"

    return {
        "actual_bytes_per_sec": actual_bytes_per_sec,
        "regime": regime,
        "breakpoint_bytes_per_sec": breakpoint_bytes_per_sec,
    }


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--quota-bytes-per-sec", type=float, required=True, help="The R you configured with rpk cluster quotas alter.")
    p.add_argument("--record-size-bytes", type=float, default=1700, help="Average record size, for a records/sec readout.")
    p.add_argument("--duration-sec", type=float, default=None, help="If given, also reports total bytes/records over this window.")
    p.add_argument("--direction", choices=["fetch", "produce"], default="fetch")
    p.add_argument("--fetch-max-bytes", type=int, default=50 * 1024 * 1024, help="Consumer fetch.max.bytes (fetch direction only).")
    p.add_argument("--max-partition-fetch-bytes", type=int, default=1024 * 1024, help="Consumer max.partition.fetch.bytes (fetch direction only).")
    p.add_argument("--partitions", type=int, default=1, help="Partitions this client reads from (fetch direction only).")
    p.add_argument("--batch-size-bytes", type=int, default=16 * 1024, help="Producer batch.size (produce direction only).")
    p.add_argument("--throttle-delay-cap-sec", type=float, default=30.0, help="max_kafka_throttle_delay_ms, in seconds.")
    p.add_argument("--min-request-interval-sec", type=float, default=0.001, help="Floor on request cadence from RTT/processing, independent of the quota.")
    p.add_argument("--slip-through-bytes", type=float, default=None,
                   help="Use a calibrated S instead of the structural estimate from fetch/batch settings. "
                        "See the lab's calibration data for measured values per client/config.")
    args = p.parse_args()

    slip_through_bytes, calibrated = effective_slip_through_bytes(args)
    result = predict(args.quota_bytes_per_sec, slip_through_bytes, args.throttle_delay_cap_sec, args.min_request_interval_sec)

    source = "calibrated" if calibrated else "structural estimate, not yet calibrated"
    print(f"Slip-through size (S): {slip_through_bytes:,.0f} bytes  [{source}]")
    if not calibrated:
        print("See the lab's calibration data for a real measured value.")
    print(f"Breakpoint (R*  =  S / throttle_delay_cap): {result['breakpoint_bytes_per_sec']:,.0f} bytes/sec")
    print(f"Regime: {result['regime']}")
    print(f"Predicted actual throughput (A): {result['actual_bytes_per_sec']:,.0f} bytes/sec "
          f"({result['actual_bytes_per_sec'] / args.record_size_bytes:,.1f} records/sec at {args.record_size_bytes:,.0f}B records)")
    if result["regime"] == "floor":
        print(f"\nYou configured R={args.quota_bytes_per_sec:,.0f} B/s, well below the breakpoint. Lowering R further will "
              f"NOT reduce throughput below ~{result['actual_bytes_per_sec']:,.0f} B/s. To go lower, shrink the "
              f"client's own {'fetch.max.bytes / max.partition.fetch.bytes' if args.direction == 'fetch' else 'batch.size'}, "
              f"or lower --throttle-delay-cap-sec (max_kafka_throttle_delay_ms) instead.")

    if args.duration_sec:
        total_bytes = result["actual_bytes_per_sec"] * args.duration_sec
        print(f"\nOver {args.duration_sec:,.0f}s: ~{total_bytes:,.0f} bytes (~{total_bytes / args.record_size_bytes:,.0f} records)")


if __name__ == "__main__":
    main()
