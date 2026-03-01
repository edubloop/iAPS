#!/usr/bin/env python3
"""
TIR Phase 1A coverage validator.

Generates source-level and window-level data coverage for:
- glucose
- insulin_basal
- insulin_bolus
- carbs

Usage:
  python3 BuildTools/tir_coverage_report.py --data-dir "/path/to/iaps records"
  python3 BuildTools/tir_coverage_report.py --data-dir "/path" --windows 7 14 30 90
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional
import xml.etree.ElementTree as ET


METRICS = ("glucose", "insulin_basal", "insulin_bolus", "carbs")


@dataclass
class TimedMetric:
    metric: str
    source: str
    timestamp: datetime


def parse_dt(value) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        ts = float(value)
        if ts > 1e12:
            ts /= 1000.0
        if ts > 1e9:
            return datetime.fromtimestamp(ts, tz=timezone.utc)
        return None
    if not isinstance(value, str):
        return None

    s = value.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"

    for fmt in (None, "%Y-%m-%d %H:%M:%S %z", "%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            if fmt is None:
                dt = datetime.fromisoformat(s)
            else:
                dt = datetime.strptime(s, fmt)
            if dt.tzinfo is None:
                return dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except ValueError:
            continue
    return None


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def as_list(value) -> List[dict]:
    if isinstance(value, list):
        return [x for x in value if isinstance(x, dict)]
    if isinstance(value, dict):
        for key in ("result", "entries", "data"):
            if isinstance(value.get(key), list):
                return [x for x in value[key] if isinstance(x, dict)]
        return [value]
    return []


def first_dt(item: dict, keys: Iterable[str]) -> Optional[datetime]:
    for key in keys:
        if key in item:
            dt = parse_dt(item[key])
            if dt is not None:
                return dt
    return None


def collect_iaps_local(base: Path) -> List[TimedMetric]:
    out: List[TimedMetric] = []

    # monitor glucose
    glucose = load_json(base / "monitor" / "glucose.json")
    for row in as_list(glucose):
        if "glucose" in row:
            dt = first_dt(row, ("dateString", "display_time", "date", "created_at", "timestamp", "time"))
            if dt:
                out.append(TimedMetric("glucose", "iaps-monitor", dt))

    # monitor pump history
    pump = load_json(base / "monitor" / "pumphistory-24h-zoned.json")
    for row in as_list(pump):
        t = str(row.get("_type", "")).lower()
        dt = first_dt(row, ("timestamp", "time", "created_at", "date"))
        if not dt:
            continue
        if "bolus" in t:
            out.append(TimedMetric("insulin_bolus", "iaps-monitor", dt))
        if "basal" in t:
            out.append(TimedMetric("insulin_basal", "iaps-monitor", dt))

    # monitor carbs
    carbs = load_json(base / "monitor" / "carbhistory.json")
    for row in as_list(carbs):
        has_carb = any(isinstance(row.get(k), (int, float)) for k in ("carbs", "carbInput", "carbohydrates"))
        if not has_carb:
            continue
        dt = first_dt(row, ("created_at", "timestamp", "time", "date"))
        if dt:
            out.append(TimedMetric("carbs", "iaps-monitor", dt))

    # upload snapshots (older historical fragments)
    upload_files = {
        "uploaded-glucose.json": "glucose",
        "uploaded-pumphistory.json": "pump",
        "uploaded-carbs.json": "carbs",
    }

    for filename, mode in upload_files.items():
        payload = load_json(base / "upload" / filename)
        for row in as_list(payload):
            dt = first_dt(row, ("dateString", "display_time", "date", "created_at", "timestamp", "time"))
            if not dt:
                continue
            if mode == "glucose":
                if "glucose" in row:
                    out.append(TimedMetric("glucose", "iaps-upload", dt))
            elif mode == "carbs":
                out.append(TimedMetric("carbs", "iaps-upload", dt))
            elif mode == "pump":
                t = str(row.get("_type") or row.get("eventType") or row.get("type") or "").lower()
                if "bolus" in t:
                    out.append(TimedMetric("insulin_bolus", "iaps-upload", dt))
                if "basal" in t:
                    out.append(TimedMetric("insulin_basal", "iaps-upload", dt))

    return out


def collect_tidepool(base: Path) -> List[TimedMetric]:
    out: List[TimedMetric] = []
    path = base / "TidepoolExport.json"
    if not path.exists():
        return out

    payload = load_json(path)
    if not isinstance(payload, list):
        return out

    for row in payload:
        if not isinstance(row, dict):
            continue
        dt = first_dt(row, ("time", "deviceTime", "localTime"))
        if not dt:
            continue
        t = str(row.get("type", "")).lower()
        if t == "cbg":
            out.append(TimedMetric("glucose", "tidepool", dt))
        elif t == "bolus":
            out.append(TimedMetric("insulin_bolus", "tidepool", dt))
        elif t == "basal":
            out.append(TimedMetric("insulin_basal", "tidepool", dt))
        elif t in ("food", "carb", "wizard"):
            out.append(TimedMetric("carbs", "tidepool", dt))

    return out


def collect_apple_health(base: Path) -> List[TimedMetric]:
    out: List[TimedMetric] = []
    path = base / "apple_health_export" / "export.xml"
    if not path.exists():
        return out

    for _, elem in ET.iterparse(path, events=("end",)):
        if elem.tag != "Record":
            continue
        t = elem.attrib.get("type", "")
        dt = parse_dt(elem.attrib.get("startDate"))
        if dt is None:
            elem.clear()
            continue

        if t == "HKQuantityTypeIdentifierBloodGlucose":
            out.append(TimedMetric("glucose", "apple-health", dt))
        elif t == "HKQuantityTypeIdentifierDietaryCarbohydrates":
            out.append(TimedMetric("carbs", "apple-health", dt))
        elif t == "HKQuantityTypeIdentifierInsulinDelivery":
            out.append(TimedMetric("insulin_bolus", "apple-health", dt))

        elem.clear()

    return out


def source_metric_summary(points: List[TimedMetric]) -> List[dict]:
    grouped: Dict[tuple, List[datetime]] = defaultdict(list)
    for p in points:
        grouped[(p.source, p.metric)].append(p.timestamp)

    rows = []
    for (source, metric), timestamps in sorted(grouped.items()):
        rows.append(
            {
                "source": source,
                "metric": metric,
                "records": len(timestamps),
                "start": min(timestamps).isoformat(),
                "end": max(timestamps).isoformat(),
            }
        )
    return rows


def window_coverage(points: List[TimedMetric], windows: List[int], analysis_end: datetime) -> List[dict]:
    by_metric: Dict[str, List[datetime]] = defaultdict(list)
    by_metric_source: Dict[tuple, List[datetime]] = defaultdict(list)
    for p in points:
        by_metric[p.metric].append(p.timestamp)
        by_metric_source[(p.metric, p.source)].append(p.timestamp)

    report = []
    for days in windows:
        start = analysis_end - timedelta(days=days)
        metrics = {}
        caveats = []

        for metric in METRICS:
            ts = by_metric.get(metric, [])
            count = sum(1 for t in ts if start <= t <= analysis_end)
            has_data = count > 0

            by_source = {}
            for (m, source), src_ts in by_metric_source.items():
                if m != metric:
                    continue
                src_count = sum(1 for t in src_ts if start <= t <= analysis_end)
                if src_count > 0:
                    by_source[source] = src_count

            metrics[metric] = {
                "has_data": has_data,
                "record_count": count,
                "by_source": by_source,
            }

        if not metrics["carbs"]["has_data"]:
            caveats.append("Carb data unavailable for this window; meal-specific attributions should be downgraded")

        if not metrics["insulin_basal"]["has_data"] and not metrics["insulin_bolus"]["has_data"]:
            caveats.append("Insulin data unavailable for this window; constraint/stacking factors may be incomplete")

        report.append(
            {
                "window_days": days,
                "analysis_start": start.isoformat(),
                "analysis_end": analysis_end.isoformat(),
                "metrics": metrics,
                "caveats": caveats,
            }
        )

    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate TIR MVP coverage report")
    parser.add_argument("--data-dir", required=True, help="Path to iAPS records directory")
    parser.add_argument("--windows", nargs="*", type=int, default=[7, 14, 30, 90], help="Coverage windows in days")
    parser.add_argument("--output", default="", help="Optional output JSON path")
    args = parser.parse_args()

    base = Path(args.data_dir)
    if not base.exists():
        raise SystemExit(f"Data directory does not exist: {base}")

    points: List[TimedMetric] = []
    points.extend(collect_iaps_local(base))
    points.extend(collect_tidepool(base))
    points.extend(collect_apple_health(base))

    if not points:
        raise SystemExit("No data points found")

    analysis_end = max(p.timestamp for p in points)

    payload = {
        "generated_at": datetime.now(tz=timezone.utc).isoformat(),
        "analysis_end": analysis_end.isoformat(),
        "source_metric_summary": source_metric_summary(points),
        "window_coverage": window_coverage(points, args.windows, analysis_end),
    }

    output = json.dumps(payload, indent=2)
    print(output)

    if args.output:
        Path(args.output).write_text(output + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
